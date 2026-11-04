provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "collab-platform-aws"
      Environment = "collab"
      ManagedBy   = "terraform"
    }
  }
}

# Teardown: all resources removed, so Terraform destroys everything in state.
# To rebuild the stack, revert the teardown commit that removed them.
