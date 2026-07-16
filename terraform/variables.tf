variable "aws_region" {
  type        = string
  description = "האזור הגאוגרפי ב-AWS שבו יוקמו כל משאבי הפרויקט"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "שם הסביבה לצורך תיוג ואחידות של משאבים"
  default     = "asterra-prod"
}

variable "allowed_rdp_ip" {
  type        = string
  description = "טווח כתובות ה-IP המורשה להתחברות RDP אל תחנת העבודה הפרטית"
  default     = "0.0.0.0/0" # בראיון נסביר שבפרודקשן נחליף ל-IP ספציפי של המפתח לאבטחה מחמירה
}

variable "rdp_username" {
  type        = string
  description = "The username for the RDP connection to the GIS workspace server"
  default     = "asterra_dev"
}

variable "rdp_password" {
  type        = string
  description = "The password for the RDP connection to the GIS workspace server"
  sensitive   = true
}

variable "wp_db_password" {
  type        = string
  description = "The root database password for the WordPress MySQL container"
  sensitive   = true
}