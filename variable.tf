#var
variable "app_name" {
  type    = string
  default = "webapp"
}

variable "app_domain" {
  type    = string
  default = "thatdorinda.com"
}

variable "app_port" {
  type    = number
  default = 80
}

variable "db_name" {
  type    = string
  default = "webappdb"
}

variable "db_user" {
  type    = string
  default = "webappuser"
}

variable "db_password" {
  type    = string
  default = "Admin123"
}
