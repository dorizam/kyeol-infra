# ALB Module
# 무한 루프 방지를 위해 HTTP Forward, HTTPS도 Forward 방식

#========================================
# Application Load Balancer
#========================================
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb-ext"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  enable_deletion_protection = false # Prod에서는 true

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-ext"
  }
}

#========================================
# Target Groups
#========================================
# Backend Target Group (Port 8000)
resource "aws_lb_target_group" "backend" {
  name        = "${var.project_name}-${var.environment}-tg-backend"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # EKS Pod IP 직접 등록

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg-backend"
  }
}

# Storefront Target Group (Port 3000)
resource "aws_lb_target_group" "storefront" {
  name        = "${var.project_name}-${var.environment}-tg-storefront"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg-storefront"
  }
}

#========================================
# HTTP Listener (Forward - 리다이렉트 X!)
# 트러블슈팅 6-3: 무한 루프 방지
#========================================
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # 기본: Storefront로 Forward
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.storefront.arn
  }
}

# HTTP Listener Rule: /graphql/* -> Backend
resource "aws_lb_listener_rule" "http_backend_graphql" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/graphql/*", "/graphql"]
    }
  }
}

# HTTP Listener Rule: /media/* -> Backend
resource "aws_lb_listener_rule" "http_backend_media" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/media/*"]
    }
  }
}

# HTTP Listener Rule: /admin/* -> Backend
resource "aws_lb_listener_rule" "http_backend_admin" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 120

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/admin/*"]
    }
  }
}

# HTTP Listener Rule: /thumbnail/* -> Backend (트러블슈팅 27)
resource "aws_lb_listener_rule" "http_backend_thumbnail" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 130

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/thumbnail/*"]
    }
  }
}

#========================================
# HTTPS Listener (선택적 - ACM 인증서 있을 때만)
#========================================
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.storefront.arn
  }
}

# HTTPS Backend Rules (인증서 있을 때만)
# HTTPS Backend Rules (인증서 있을 때만)
resource "aws_lb_listener_rule" "https_backend_graphql" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/graphql/*", "/graphql"]
    }
  }
}

resource "aws_lb_listener_rule" "https_backend_media" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/media/*"]
    }
  }
}

resource "aws_lb_listener_rule" "https_backend_admin" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 120

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/admin/*"]
    }
  }
}

resource "aws_lb_listener_rule" "https_backend_thumbnail" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 130

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/thumbnail/*"]
    }
  }
}
