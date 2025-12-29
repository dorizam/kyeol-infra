# CloudFront + S3 Module
# 정적 호스팅 (Dashboard) + 미디어 (상품 이미지) + 동적 오리진 (ALB)

#========================================
# S3 Bucket for Static Assets (Dashboard)
#========================================
resource "aws_s3_bucket" "static" {
  bucket = "${var.project_name}-${var.environment}-s3-static"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-static"
  }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#========================================
# S3 Bucket for Media (상품 이미지, 썸네일 등)
# 트러블슈팅 14: localhost 이미지 URL 문제 해결
#========================================
resource "aws_s3_bucket" "media" {
  bucket = "${var.project_name}-${var.environment}-s3-media"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-media"
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

#========================================
# CloudFront Origin Access Control (OAC)
#========================================
resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${var.project_name}-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.project_name}-${var.environment}-oac-media"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

#========================================
# S3 Bucket Policy for CloudFront
#========================================
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.static.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.media.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

#========================================
# CloudFront Function (index.html 자동 추가)
# 트러블슈팅 11: SPA 라우팅 지원
#========================================
resource "aws_cloudfront_function" "index_rewrite" {
  name    = "${var.project_name}-${var.environment}-index-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite requests to index.html for SPA routing"
  publish = true

  code = <<-EOT
    function handler(event) {
        var request = event.request;
        var uri = request.uri;
        
        // Dashboard 경로 처리
        if (uri.startsWith('/dashboard')) {
            // 확장자가 없으면(파일이 아니면) 무조건 /dashboard/index.html로 라우팅 (SPA)
            if (!uri.includes('.')) {
                request.uri = '/dashboard/index.html';
            } 
            // 슬래시로 끝나면 index.html 붙임
            else if (uri.endsWith('/')) {
                request.uri = uri + 'index.html';
            }
        }
        
        return request;
    }
  EOT
}

#========================================
# CloudFront Function (루트 경로 리다이렉트)
# 트러블슈팅 27: 루트 경로를 /default-channel로 리다이렉트
#========================================
resource "aws_cloudfront_function" "root_redirect" {
  name    = "${var.project_name}-${var.environment}-root-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect root path to /default-channel"
  publish = true

  code = <<-EOT
    function handler(event) {
        var request = event.request;
        var uri = request.uri;
        
        // 루트 경로를 /default-channel로 리다이렉트
        if (uri === '/' || uri === '') {
            return {
                statusCode: 301,
                statusDescription: 'Moved Permanently',
                headers: {
                    'location': { value: '/default-channel' },
                    'cache-control': { value: 'max-age=3600' }
                }
            };
        }
        
        return request;
    }
  EOT
}

#========================================
# CloudFront Distribution
#========================================
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-${var.environment} distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 아시아 포함
  aliases             = var.custom_domain != "" ? [var.custom_domain] : []

  # Origin 1: ALB (동적 콘텐츠)
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # 중요: http-only로 설정 (SSL Mismatch 방지)
      # 트러블슈팅 5-3, 33 참고: HTTPS Listener가 있으면 https-only 권장
      origin_protocol_policy = var.certificate_arn != "" ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin 2: S3 (정적 콘텐츠 - Dashboard)
  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = "s3-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  # Origin 3: S3 (미디어 - 상품 이미지)
  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "s3-media"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  # 기본 동작: ALB (Storefront)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization", "Accept-Language"]

      cookies {
        forward = "all"
      }
    }

    # 루트 경로 리다이렉트 Function 연결
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.root_redirect.arn
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0 # 동적 콘텐츠는 캐시 안함
  }

  # Dashboard 동작: S3
  ordered_cache_behavior {
    path_pattern     = "/dashboard/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.index_rewrite.arn
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # GraphQL 동작: ALB (캐시 안함)
  ordered_cache_behavior {
    path_pattern     = "/graphql/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization", "Content-Type"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # Media 동작: S3 미디어 버킷 (상품 이미지, 썸네일)
  # 트러블슈팅 14: localhost 이미지 URL 문제 해결
  ordered_cache_behavior {
    path_pattern     = "/media/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-media"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000  # 이미지는 장기 캐시
  }

  # Thumbnails 동작: S3 미디어 버킷 (썸네일 캐시 파일)
  # Backend가 생성한 썸네일은 S3에 저장되고 이 경로로 서빙됨
  ordered_cache_behavior {
    path_pattern     = "/thumbnails/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-media"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000  # 썸네일도 장기 캐시
  }

  # Thumbnail 동작: ALB (Backend에서 동적 생성)
  # 중요: 썸네일은 S3에 저장되지 않고 Backend에서 실시간 생성됨
  ordered_cache_behavior {
    path_pattern     = "/thumbnail/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin"]

      cookies {
        forward = "none"
      }
    }

    # 중요: allow-all로 설정해야 Next.js Image Optimization이 http:// URL을 fetch할 수 있음
    # 트러블슈팅 34: PUBLIC_URL=http 시 썸네일 403 에러 해결
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 86400     # 썸네일 캐시 1일
    max_ttl                = 31536000  # 최대 1년
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.custom_domain == ""
    acm_certificate_arn            = var.custom_domain != "" ? var.certificate_arn : null
    ssl_support_method             = var.custom_domain != "" ? "sni-only" : null
    minimum_protocol_version       = var.custom_domain != "" ? "TLSv1.2_2021" : null
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront"
  }
}
