resource "aws_s3_bucket" "jfr" {
  count         = var.pg_jfr_enabled ? 1 : 0
  bucket        = "${var.project}-jfr-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "jfr" {
  count                   = var.pg_jfr_enabled ? 1 : 0
  bucket                  = aws_s3_bucket.jfr[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "jfr_upload" {
  count = var.pg_jfr_enabled ? 1 : 0
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.jfr[0].arn}/*"]
  }
}

resource "aws_iam_role_policy" "jfr_upload" {
  count  = var.pg_jfr_enabled ? 1 : 0
  name   = "jfr-upload"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.jfr_upload[0].json
}
