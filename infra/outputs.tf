output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "api_gateway_security_group_id" {
  description = "ID of the API Gateway security group"
  value       = aws_security_group.api_gateway.id
} 