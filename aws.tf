provider "aws" {
  version    = "~> 2.0"
  profile = "pa1"
}

//Security Group
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = "vpc-ef968b87"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
}

//EC2
resource "aws_instance" "mywebserver" {

ami = "ami-005956c5f0f757d37"
instance_type = "t2.micro"
key_name = "deployer-key"
security_groups = ["allow_http"]
depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("/root/pawan.pem")
    host     = aws_instance.mywebserver.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
  }
  tags = {
    Name = "webserver"
  }

}

resource "aws_ebs_volume" "EBS1" {
  availability_zone = aws_instance.mywebserver.availability_zone
  size              = 1
  depends_on = [
    aws_instance.mywebserver,
  ]
tags = {
    Name = "Webserver_EBS1"
  }
}


resource "aws_volume_attachment" "EBS1_attach" {
  device_name = "/dev/sdh"
  volume_id   = "$aws_ebs_volume.EBS1.id"
  instance_id = "$aws_instance.mywebserver.id"
  force_detach = true
  depends_on = [
    aws_ebs_volume.EBS1,
  ]
}


output "myos_ip" {
  value = aws_instance.mywebserver.public_ip
}


resource "null_resource" "nulllocal2"  {
        provisioner "local-exec" {
            command = "echo  $aws_instance.mywebserver.public_ip > publicip.txt"
        }
}


resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.EBS1_attach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("/root/pawan.pem")
    host     = aws_instance.mywebserver.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/pawankulaura/test_html_code.git /var/www/html/"
    ]
  }
}



resource "null_resource" "nulllocal1"  {


depends_on = [
    null_resource.nullremote3,
  ]

        provisioner "local-exec" {
            command = "firefox  $aws_instance.mywebserver.public_ip"
        }
}



resource "null_resource" "nulllocal4"  {
        provisioner "local-exec" {
            command = "echo  $aws_cloudfront_distribution.s3_distribution.domain_name > domain.txt"
        }
}


//Cloud_front

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Create origin access identity"
}
locals {
  s3_origin_id = "s3_origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "$aws_s3_bucket.upload.bucket_regional_domain_name"
    origin_id   = "$local.s3_origin_id"

s3_origin_config {
  origin_access_identity = "$aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path"
}
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "$local.s3_origin_id"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

 # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "$local.s3_origin_id"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "$local.s3_origin_id"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE","IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket" "upload" {
  bucket = "kulauras3bucket"
  acl    = "private"

  tags = {
    Name        = "task1"
    Environment = "dev"
  }
}



resource "aws_s3_bucket_object" "pic" {
  bucket = "$kulauras3bucket.upload.id"
  key    = "image.jpeg"
  source ="image.jpeg"
  content_type = "image/jpeg"
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["$kulauras3bucket.upload.arn/*"]

    principals {
      type        = "AWS"
      identifiers = ["$aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["$kulauras3bucket.upload.arn"]

    principals {
      type        = "AWS"
      identifiers = ["$aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn"]
    }
  }
}

resource "aws_iam_policy" "s3_policy" {
  name   = "example_policy"
  path   = "/"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}
