""" Combines three resources creation - 
1. AWS EC2 Instance with Amazon Linux AMI and keypair specified
2. AWS Keypair for the instance
3. The SSH Keys (RSA 4096) (Public and Private) for the keypair along with a local file resource to save it.
"""
resource "tls_private_key" "nautilus-pk" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "nautilus-kp" {
    key_name = "nautilus-kp"
    public_key = tls_private_key.nautilus-pk.public_key_openssh
}

resource "local_file" "private_key" {
    filename = "${aws_key_pair.nautilus-kp.key_name}.pem"
    content = tls_private_key.nautilus-pk.private_key_pem
    file_permission = "0400"
}

resource "aws_instance" "nautilus-ec2" {
    ami = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    key_name = aws_key_pair.nautilus-kp.key_name
}
