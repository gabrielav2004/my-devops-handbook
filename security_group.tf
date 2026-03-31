""" Terraform Definition for Creating a Security Group with two ingress rules for HTTP and SSH """
# main.tf
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "nautilus-sg" {
    name = "nautilus-sg"
    description = "Security group for Nautilus App Servers"
    vpc_id = data.aws_vpc.default.id

    tags = {
        name = "nautilus-sg"
    }
}

resource "aws_vpc_security_group_ingress_rule" "http_allow" {
    security_group_id = aws_security_group.nautilus-sg.id
    cidr_ipv4 = "0.0.0.0/0"
    from_port = 80
    to_port = 80
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_allow" {
    security_group_id = aws_security_group.nautilus-sg.id
    cidr_ipv4 = "0.0.0.0/0"
    from_port = 22
    to_port = 22
    ip_protocol = "tcp"
}
