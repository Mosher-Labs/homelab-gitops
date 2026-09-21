# Read-only lookups against zones owned by the separate cloudflare-management
# repo's Terraform state — this stack never creates or modifies a zone.
data "cloudflare_zone" "zones" {
  for_each = local.zone_names

  filter = {
    name    = each.value
    account = { id = var.cloudflare_account_id }
  }
}
