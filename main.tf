resource "aws_vpc" "kubernetes" {
  cidr_block = "10.43.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "kubernetes" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "10.43.0.0/16"
  availability_zone = "us-west-2a"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.kubernetes.id}"
}

resource "aws_route_table" "kubernetes" {
    vpc_id = "${aws_vpc.kubernetes.id}"
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.gw.id}"
    }
}

resource "aws_route_table_association" "kubernetes" {
  subnet_id = "${aws_subnet.kubernetes.id}"
  route_table_id = "${aws_route_table.kubernetes.id}"
}

resource "aws_instance" "etcd" {
    count = 3
    ami = "ami-5e63d13e"
    instance_type = "t2.micro"

    subnet_id = "${aws_subnet.kubernetes.id}"
    private_ip = "${cidrhost("10.43.0.0/16", 10 + count.index)}"
    associate_public_ip_address = true

    availability_zone = "us-west-2a"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    key_name = "${var.aws_key_name}"
    tags {
      Owner = "kuldeep"
      Name = "etcd-${count.index}"
      ansibleFilter = "Kubernetes01"
      ansibleNodeType = "etcd"
      ansibleNodeName = "etcd${count.index}"
    }
}

resource "aws_instance" "controller" {
    count = 3
    ami = "ami-5e63d13e"
    instance_type = "t2.micro"

    subnet_id = "${aws_subnet.kubernetes.id}"
    private_ip = "${cidrhost("10.43.0.0/16", 20 + count.index)}"
    associate_public_ip_address = true

    availability_zone = "us-west-2a"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    key_name = "${var.aws_key_name}"

    tags {
      Owner = "kuldeep"
      Name = "controller-${count.index}"
      ansibleFilter = "Kubernetes01"
      ansibleNodeType = "controller"
      ansibleNodeName = "controller${count.index}"
    }
}

resource "aws_instance" "worker" {
    count = 3
    ami = "ami-5e63d13e"
    instance_type = "t2.micro"

    subnet_id = "${aws_subnet.kubernetes.id}"
    private_ip = "${cidrhost("10.43.0.0/16", 30 + count.index)}"
    associate_public_ip_address = true
    source_dest_check = false

    availability_zone = "us-west-2a"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    key_name = "${var.aws_key_name}"

    tags {
      Owner = "kuldeep"
      Name = "worker-${count.index}"
      ansibleFilter = "Kubernetes01"
      ansibleNodeType = "worker"
      ansibleNodeName = "worker${count.index}"
    }
}


resource "aws_iam_role" "kubernetes" {
  name = "kubernetes"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [ { "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" } ]
}
EOF
}

resource "aws_iam_role_policy" "kubernetes" {
  name = "kubernetes"
  role = "${aws_iam_role.kubernetes.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Action" : ["ec2:*"], "Effect": "Allow", "Resource": ["*"] },
    { "Action" : ["elasticloadbalancing:*"], "Effect": "Allow", "Resource": ["*"] },
    { "Action": "route53:*", "Effect": "Allow",  "Resource": ["*"] },
    { "Action": "ecr:*", "Effect": "Allow", "Resource": "*" }
  ]
}
EOF
}

resource  "aws_iam_instance_profile" "kubernetes" {
 name = "kubernetes"
 roles = ["${aws_iam_role.kubernetes.name}"]
}


resource "aws_elb" "kubernetes_api" {
    name = "kube-api"
    instances = ["${aws_instance.controller.*.id}"]
    subnets = ["${aws_subnet.kubernetes.id}"]
    cross_zone_load_balancing = false

    security_groups = ["${aws_security_group.kubernetes_api.id}"]

    listener {
      lb_port = 6443
      instance_port = 6443
      lb_protocol = "TCP"
      instance_protocol = "TCP"
    }

    health_check {
      healthy_threshold = 2
      unhealthy_threshold = 2
      timeout = 15
      target = "HTTP:8080/healthz"
      interval = 30
    }
}


resource "aws_security_group" "kubernetes" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  name = "kubernetes"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }

  # Allow all traffic from the API ELB
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.kubernetes_api.id}"]
  }

  # Allow all traffic from control host IP
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "kubernetes_api" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  name = "kubernetes-api"

  # Allow inbound traffic to the port used by Kubernetes API HTTPS
  ingress {
    from_port = 6443
    to_port = 6443
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


