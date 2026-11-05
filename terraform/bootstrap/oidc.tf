data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer validates this thumbprint for GitHub. The API still requires one.
  thumbprint_list = [replace(data.tls_certificate.github.certificates[0].sha1_fingerprint, ":", "")]

  tags = {
    Project   = local.name_prefix
    ManagedBy = "terraform-bootstrap"
  }

  lifecycle {
    ignore_changes = [thumbprint_list]
  }
}
