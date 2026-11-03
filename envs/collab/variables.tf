variable "allowed_cidr" {
  type        = string
  description = "The only source allowed to reach the load balancer."
  sensitive   = true
}
