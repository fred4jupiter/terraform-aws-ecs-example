output "id" {
  value = aws_ecs_service.fredbet-service.id
}

output "name" {
  value = aws_ecs_service.fredbet-service.name
}

output "lb_zone_id" {
  value = aws_lb.alb.zone_id
}

output "lb_dns_name" {
  value = aws_lb.alb.dns_name
}
