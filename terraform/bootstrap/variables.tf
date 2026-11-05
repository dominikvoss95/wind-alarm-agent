variable "region" {
  description = "AWS region for the state bucket and the GitHub Actions roles."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = var.region == "eu-central-1"
    error_message = "The application stack and these roles are scoped to eu-central-1."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false when the account already has one for token.actions.githubusercontent.com, then import is unnecessary."
  type        = bool
  default     = true
}
