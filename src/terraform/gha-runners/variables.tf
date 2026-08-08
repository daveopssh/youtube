variable "env_prefix" {
  description = "Environment prefix"
  type        = string
  default     = "demo"
}

variable "idle_config" {
  description = "Time periods that keep idle runners active. Empty means scale down to zero."
  type = list(object({
    cron             = string
    timeZone         = string
    idleCount        = number
    evictionStrategy = optional(string, "oldest_first")
  }))
  default = []
}


variable "instance_target_capacity_type" {
  description = "Runner instance lifecycle: spot or on-demand."
  type        = string
  default     = "spot"

  validation {
    condition     = contains(["spot", "on-demand"], var.instance_target_capacity_type)
    error_message = "The instance target capacity type must be spot or on-demand."
  }
}

variable "runner_instance_types" {
  description = "EC2 instance types used by GitHub Actions runners."
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "github_runner_module_version" {
  type    = string
  default = "7.10.1"
}

variable "github_app_id" {
  type    = string
  default = "placeholder"
}
