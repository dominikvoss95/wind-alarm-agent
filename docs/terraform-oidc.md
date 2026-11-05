# Terraform mit GitHub Actions und AWS OIDC

Die Pipeline in `.github/workflows/terraform.yml` nimmt kurzlebige AWS-Credentials über GitHub OIDC an. Es gibt keine langlebigen Access Keys und keinen Secret `AWS_ACCESS_KEY_ID`.

Region: **eu-central-1**. Repository: **dominikvoss95/wind-alarm-agent**. Workflow-Datei: **`.github/workflows/terraform.yml`**.

Zwei Rollen:

| Rolle | Wann | Darf |
| --- | --- | --- |
| `wind-alarm-agent-gha-plan` | Pull Request und Plan auf `main` | Lesen, plus State-Datei schreiben (Refresh) |
| `wind-alarm-agent-gha-apply` | nur `main`, nur Environment `production` | Anlegen und Ändern der Ressourcen aus `terraform/` |

Die Apply-Rolle vertraut nur diesem Subjekt:

`repo:dominikvoss95/wind-alarm-agent:environment:production`

zusätzlich `ref = refs/heads/main` und `workflow_ref` genau auf `terraform.yml@refs/heads/main`. Ein Pull Request kann sie nicht annehmen, auch wenn der Workflow im PR geändert wird.

`terraform/bootstrap` legst du einmal lokal an. Die Actions-Pipeline wendet nur `terraform/` an und kann die eigenen Rollen nicht erweitern.

Azure liegt in `terraform/azure/` und läuft in diesem Workflow nicht mit. `terraform validate` meldet dort weiter Fehler im Provider-Schema (`kind = "AIServices"`, Block `sku`). Das ist der bisherige Stand.

## Einmalige Schritte

Reihenfolge einhalten. Das GitHub-Environment **vor** den Variablen anlegen. Sonst erzeugt GitHub beim ersten Apply ein Environment ohne Reviewer, und ein Push auf `main` würde sofort anwenden.

### 1. Werkzeuge

AWS CLI v2, angemeldet mit einem Admin-Benutzer, Region `eu-central-1`. Terraform **1.11 oder neuer** (die Pipeline pinnt **1.17.1**).

```bash
aws sts get-caller-identity --region eu-central-1
terraform version
```

Die Account-ID aus der Ausgabe brauchst du unten. Nicht ins Repository schreiben.

### 2. Prüfen, ob der OIDC-Provider schon existiert

Ein Account hat höchstens einen Provider für `token.actions.githubusercontent.com`.

```bash
aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text
```

Leere Ausgabe: Schritt 3 legt ihn an. Eine ARN: vor `terraform apply` importieren (Schritt 3b), sonst bricht Apply mit `EntityAlreadyExists` ab.

Konsole, falls du ihn von Hand anlegen willst: IAM → Identity providers → Add provider → OpenID Connect → Provider URL `https://token.actions.githubusercontent.com` → Audience `sts.amazonaws.com` → Get thumbprint → Add. Danach trotzdem Schritt 3b.

### 3. Bootstrap anwenden

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Das legt an:

- S3-Bucket `wind-alarm-agent-tfstate-<ACCOUNT_ID>` (Versionierung, Verschlüsselung, öffentlich gesperrt)
- OIDC-Provider, falls `create_oidc_provider` true ist (Standard)
- Rollen `wind-alarm-agent-gha-plan` und `wind-alarm-agent-gha-apply`

State dieser einmaligen Stacks liegt lokal in `terraform/bootstrap/terraform.tfstate`. Die Datei ist per `.gitignore` ausgeschlossen. Privat sichern. Nicht committen.

### 3b. Provider existiert schon

```bash
cd terraform/bootstrap
terraform init
terraform import 'aws_iam_openid_connect_provider.github[0]' \
  "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
terraform apply
```

Alternativ ohne Import, wenn du den Provider nicht mit Terraform verwalten willst:

```bash
terraform apply -var=create_oidc_provider=false
```

### 4. Werte ablesen

```bash
terraform output -raw plan_role_arn
terraform output -raw apply_role_arn
terraform output -raw state_bucket_name
```

Das sind keine Secrets. Nicht unter GitHub Secrets ablegen.

### 5. GitHub-Environment `production`

Im Repository: **Settings → Environments → New environment**.

- Name exakt: `production`
- **Required reviewers**: dich selbst
- **Deployment branches and tags**: Selected branches → `main`

Ohne Required reviewers ist ein Push auf `main` keine Freigabe.

### 6. Repository-Variablen

**Settings → Secrets and variables → Actions → Tab Variables** (nicht Secrets).

| Name | Wert |
| --- | --- |
| `AWS_PLAN_ROLE_ARN` | Ausgabe `plan_role_arn` |
| `AWS_APPLY_ROLE_ARN` | Ausgabe `apply_role_arn` |
| `TF_STATE_BUCKET` | Ausgabe `state_bucket_name` |

Keine Variable `AWS_ACCESS_KEY_ID` und kein `AWS_SECRET_ACCESS_KEY` anlegen.

Solange eine der drei Variablen fehlt, läuft auf Pull Requests nur `terraform validate`. Plan und Apply werden übersprungen. Ein manuelles Apply bricht dann ab.

### 7. Erster Lauf

**Actions → Terraform → Run workflow**. Branch `main`. Eingabe `confirm` exakt `apply`.

Der Apply-Job wartet auf die Freigabe im Environment `production`. Den Plan im Log lesen, dann freigeben.

Dieselbe Freigabe gilt für einen Push auf `main`, der `terraform/` oder den Workflow ändert.

Der erste Apply der Lambda-Funktion braucht ein Image `:latest` in ECR. Vorher `make push-image`, sonst schlägt nur das Erzeugen der Funktion fehl. ECR, Tabelle, Bucket und Regeln legt der Apply an.

## Was die Pipeline danach tut

- Pull Request nach `main`, wenn `terraform/` oder der Workflow geändert wurde: `terraform fmt`, `validate`, dann Plan mit der Plan-Rolle. Der Plan liegt als Artifact `tfplan-<run_id>` und als Kommentar am PR. Kein Apply.
- Push auf `main` mit denselben Pfaden: Plan, danach Apply des gespeicherten Plans. Der Apply-Job hängt am Environment `production`.
- **Run workflow** auf `main` mit `confirm=apply`: derselbe Apply, ebenfalls mit Freigabe. Anderer Text oder ein anderer Branch: Abbruch, nichts wird angewendet.
- Fork-PRs bekommen kein OIDC-Token. Dort läuft nur die Validierung.

Lokal, mit eigenen Admin-Credentials, nicht für die Pipeline:

```bash
export TF_STATE_BUCKET="$(cd terraform/bootstrap && terraform output -raw state_bucket_name)"
export AWS_REGION=eu-central-1
make tf-init
make tf-plan
make tf-apply
```

## Was die Apply-Rolle darf

Nur `eu-central-1` und nur diese Namen. Die genauen Actions stehen in `terraform/bootstrap/iam.tf`.

| Dienst | Ressource |
| --- | --- |
| ECR | Repository `wind-alarm-agent`, plus `ecr:GetAuthorizationToken` auf `*` |
| IAM | nur Rolle `wind-alarm-agent-lambda-role`. `iam:PassRole` nur an `lambda.amazonaws.com` |
| Lambda | Funktion `wind-alarm-agent` |
| S3 | Bucket `wind-alarm-web-assets-<ACCOUNT_ID>` und dessen Objekte zum Leeren (`force_destroy`) |
| S3 State | nur `wind-alarm-agent/aws.tfstate` und `wind-alarm-agent/aws.tfstate.tflock` |
| DynamoDB | Tabelle `wind-alarm-knowledge-base` |
| EventBridge | Regeln `wind-alarm-*` |
| CloudWatch | Alarme `wind-alarm-*` |

Nicht enthalten: Benutzer, OIDC-Provider, die beiden GitHub-Rollen, andere Regionen, `AdministratorAccess`, Azure.

Die Plan-Rolle hat dieselben Lese-Rechte und darf die State-Datei aktualisieren. Sie darf keine der Ressourcen oben anlegen oder löschen. Pull Requests in diesem Repository können den State lesen. Nur Personen mit Schreibrecht auf das Repository sollten PRs öffnen.

## Wenn ein Apply `AccessDenied` meldet

Neue Ressourcentypen oder andere Namen brauchen einen Eintrag in `terraform/bootstrap/iam.tf`. Danach lokal `terraform apply` in `terraform/bootstrap`. Die Pipeline kann das nicht selbst, absichtlich.

Ein fehlendes Image in ECR ist kein IAM-Fehler. Dann `make push-image` und den Apply erneut starten.
