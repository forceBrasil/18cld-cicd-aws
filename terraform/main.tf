# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
}

variable "project" {
  default = "18cld"
}

data "aws_vpc" "vpc" {
  tags {
    Name = "${var.project}"
  }
}

data "aws_subnet_ids" "all" {
  vpc_id = "${data.aws_vpc.vpc.id}"

  tags {
    Tier = "Public"
  }
}

data "aws_subnet" "public" {
  count = "${length(data.aws_subnet_ids.all.ids)}"
  id    = "${data.aws_subnet_ids.all.ids[count.index]}"
}

resource "random_shuffle" "random_subnet" {
  input        = ["${data.aws_subnet.public.*.id}"]
  result_count = 1
}

resource "aws_elb" "web" {
  name = "terraform-example-elb"

  subnets         = ["${data.aws_subnet_ids.all.ids}"]
  security_groups = ["${aws_security_group.allow-ssh.id}"]

  listener {
    instance_port     = 3000
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:3000/"
    interval            = 6
  }

  # The instances are registered automatically
  instances = ["${aws_instance.web.*.id}"]
}

resource "aws_instance" "web" {
  instance_type = "t2.micro"
  ami           = "${lookup(var.aws_amis, var.aws_region)}"

  count = 2

  subnet_id              = "${random_shuffle.random_subnet.result[0]}"
  vpc_security_group_ids = ["${aws_security_group.allow-ssh.id}"]
  key_name               = "${var.KEY_NAME}"
  iam_instance_profile = "${aws_iam_instance_profile.test_devops.id}"
  provisioner "file" {
    source      = "script.sh"
    destination = "/tmp/script.sh"
  }

  provisioner "file" {
    source      = "imagedefinitions.json"
    destination = "/tmp/imagedefinitions.json"
  }

  provisioner "file" {
    source      = "/root/.aws/config"
    destination = "/tmp/config"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/script.sh",
      "sudo /tmp/script.sh",
    ]
  }

  connection {
    user        = "${var.INSTANCE_USERNAME}"
    private_key = "${file("${var.PATH_TO_KEY}")}"
  }

  tags {
    Name = "${format("test-desvops-fiap-%03d", count.index + 1)}"
    Stage = "${var.stage}"
    Version = "${var.version}"
  }
}
