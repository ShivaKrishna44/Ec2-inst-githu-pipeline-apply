# ============================================================================
# ec2.tf  — The most basic Terraform example: one EC2 instance + one security group
# ----------------------------------------------------------------------------
# Flow: Terraform reads this file, sees two resources, and creates them in AWS.
#   1. aws_security_group.allow_tls  -> a firewall that allows SSH in, all out
#   2. aws_instance.this             -> a virtual machine attached to that firewall
# Terraform automatically figures out the security group must exist BEFORE the
# instance, because the instance references the security group's id.
# ============================================================================

# ---- Look up the OS image (AMI) ----
# AMI IDs are different in every region and old ones get retired.
# So we look the AMI up by owner and name instead of hard-coding an ID.
data "aws_ami" "practice" {
  owners      = ["973714476881"]
  most_recent = true

  filter {
    name   = "name"
    values = ["Redhat-9-DevOps-Practice*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---- The virtual machine (EC2 instance) ----
resource "aws_instance" "this" {
  ami                    = data.aws_ami.practice.id          # OS image the VM boots from (looked up above)
  vpc_security_group_ids = [aws_security_group.allow_tls.id] # Attach the firewall defined below (creates the dependency)
  instance_type          = "t3.micro"                        # Hardware size (2 vCPU / 1 GiB) — small/cheap for practice
  tags = {
    Name    = "terraform-demo"     # Friendly name shown in the AWS console
    Purpose = "terraform-practice" # Free-form label to explain why it exists
  }
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

# ---- The firewall (security group) that controls network traffic ----
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"                                          # Name of the security group in AWS
  description = "Allow TLS inbound traffic and all outbound traffic" # Human-readable description

  # Inbound rule: who is allowed to connect TO the instance
  ingress {
    from_port   = 22            # Start of the allowed port range (22 = SSH)
    to_port     = 22            # End of the allowed port range (22 = SSH)
    protocol    = "tcp"         # SSH runs over TCP
    cidr_blocks = ["0.0.0.0/0"] # Allow from any IP address (open to the world — fine for a demo, unsafe for prod)
  }

  # Outbound rule: what the instance is allowed to connect TO
  egress {
    from_port   = 0             # 0 + protocol "-1" together mean "all ports"
    to_port     = 0             # All ports
    protocol    = "-1"          # "-1" = all protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow the instance to reach any IP address
  }

  tags = {
    Name = "allow_tls" # Friendly name for the security group
  }
}
