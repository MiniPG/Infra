# ─────────────────────────────────────────────
# ALB + HTTPS (ACM) + 도메인 (Route 53)
#   노트북 → https://pg.on-me-app.com → ALB(public) → PG-Server(private, 8080)
#   - TLS는 ALB에서 종료, ALB → PG는 VPC 내부 HTTP
#   - Card-Server는 외부에 노출하지 않음 (PG만 호출)
#   - /actuator/* 는 외부 요청을 ALB에서 404로 차단 (지표는 Prometheus가 VPC 안에서 직접 수집)
# ─────────────────────────────────────────────

locals {
  pg_fqdn = "${var.pg_subdomain}.${var.domain_name}"
}

# ON:ME 도메인의 호스팅 영역: 만들지 않고 참조만 (destroy해도 ON:ME DNS는 그대로)
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ── 인증서 (무료, DNS 검증으로 자동 발급) ──
resource "aws_acm_certificate" "pg" {
  domain_name       = local.pg_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-pg" }
}

# ACM이 요구하는 검증용 CNAME 레코드를 호스팅 영역에 추가 → "이 도메인의 주인이 맞다" 증명
resource "aws_route53_record" "pg_cert_validation" {
  for_each = {
    for o in aws_acm_certificate.pg.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# 검증이 끝나 인증서가 발급될 때까지 기다림 (보통 1~5분)
resource "aws_acm_certificate_validation" "pg" {
  certificate_arn         = aws_acm_certificate.pg.arn
  validation_record_fqdns = [for r in aws_route53_record.pg_cert_validation : r.fqdn]
}

# ── ALB ──
resource "aws_lb" "pg" {
  name               = "${var.project}-pg"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # ALB는 서로 다른 AZ의 서브넷 2개 이상 필요

  tags = { Name = "${var.project}-pg" }
}

resource "aws_lb_target_group" "pg" {
  name                 = "${var.project}-pg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  target_type          = "instance"
  deregistration_delay = 30 # 대상 제거 시 진행 중 요청을 기다리는 시간 (기본 300초 → 실험 환경이라 짧게)

  # readiness: "프로세스가 살아 있다"가 아니라 "요청을 받을 준비가 됐다"일 때만 트래픽을 보냄
  # (헬스 체크는 ALB가 대상에 직접 보내므로 아래 /actuator 차단 규칙의 영향을 받지 않음)
  health_check {
    path                = "/actuator/health/readiness"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project}-pg" }
}

resource "aws_lb_target_group_attachment" "pg" {
  count            = var.pg_count
  target_group_arn = aws_lb_target_group.pg.arn
  target_id        = aws_instance.pg[count.index].id
  port             = 8080
}

# HTTP(80) → HTTPS(443) 리다이렉트
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.pg.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.pg.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # TLS 1.2 이상만 허용
  certificate_arn   = aws_acm_certificate_validation.pg.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pg.arn
  }
}

# 외부에서 /actuator/* 요청은 차단 (스레드 덤프·지표·환경 정보 노출 방지)
resource "aws_lb_listener_rule" "block_actuator" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/actuator", "/actuator/*"]
    }
  }

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# pg.on-me-app.com → ALB (별칭 레코드: ALB IP가 바뀌어도 자동으로 따라감)
resource "aws_route53_record" "pg" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.pg_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.pg.dns_name
    zone_id                = aws_lb.pg.zone_id
    evaluate_target_health = true
  }
}
