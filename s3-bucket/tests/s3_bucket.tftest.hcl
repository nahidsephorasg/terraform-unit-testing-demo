# =============================================================================
# EXAMPLE 1: Native Terraform Tests (terraform test)
# =============================================================================
#
# HOW TO RUN:
#   cd examples/s3-bucket
#   terraform init
#   terraform test
#
# WHAT HAPPENS:
#   Terraform discovers all *.tftest.hcl files in tests/ directory,
#   runs each "run" block sequentially, and reports pass/fail.
#
# REQUIREMENTS:
#   - Terraform >= 1.6 (for native tests)
#   - Terraform >= 1.7 (for mock providers — used here)
#   - No cloud credentials needed when using mocks!
#
# =============================================================================

# ---------------------------------------------------------------------------
# Mock provider: Simulates AWS without making real API calls.
# This means $0 cost and no credentials needed.
# ---------------------------------------------------------------------------
mock_provider "aws" {}

# ---------------------------------------------------------------------------
# TEST 1: Verify bucket name matches input (plan mode)
# ---------------------------------------------------------------------------
# command = plan → Fast. No resources created. Good for checking
# input-derived values (things you pass in, not things AWS generates).
# ---------------------------------------------------------------------------
run "bucket_name_matches_input" {
  command = plan

  variables {
    bucket_name = "my-learning-bucket"
  }

  # Assert: the bucket resource should use the name we passed in
  assert {
    condition     = aws_s3_bucket.this.bucket == "my-learning-bucket"
    error_message = "Bucket name should be 'my-learning-bucket', got: ${aws_s3_bucket.this.bucket}"
  }
}

# ---------------------------------------------------------------------------
# TEST 2: Input validation — bucket name too short
# ---------------------------------------------------------------------------
# expect_failures tells Terraform "this SHOULD fail validation".
# If the validation passes, the test fails (inverted logic).
# ---------------------------------------------------------------------------
run "rejects_short_bucket_name" {
  command = plan

  variables {
    bucket_name = "ab"  # Only 2 chars — violates our >= 3 rule
  }

  # We expect the bucket_name variable's validation to fail
  expect_failures = [
    var.bucket_name,
  ]
}

# ---------------------------------------------------------------------------
# TEST 3: Input validation — invalid encryption algorithm
# ---------------------------------------------------------------------------
run "rejects_invalid_sse_algorithm" {
  command = plan

  variables {
    bucket_name   = "test-bucket"
    sse_algorithm = "INVALID"  # Not AES256 or aws:kms
  }

  expect_failures = [
    var.sse_algorithm,
  ]
}

# ---------------------------------------------------------------------------
# TEST 4: Verify versioning is enabled by default (plan mode)
# ---------------------------------------------------------------------------
run "versioning_enabled_by_default" {
  command = plan

  variables {
    bucket_name = "versioned-bucket"
    # enable_versioning defaults to true, so we don't set it
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be Enabled by default"
  }
}

# ---------------------------------------------------------------------------
# TEST 5: Verify versioning can be disabled
# ---------------------------------------------------------------------------
run "versioning_can_be_disabled" {
  command = plan

  variables {
    bucket_name       = "no-versioning-bucket"
    enable_versioning = false
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "Versioning should be Suspended when disabled"
  }
}

# ---------------------------------------------------------------------------
# TEST 6: Public access block is fully locked down (apply mode)
# ---------------------------------------------------------------------------
# command = apply → Simulates full resource creation (with mocks).
# Needed when accessing set-type blocks or computed values.
# ---------------------------------------------------------------------------
run "public_access_fully_blocked" {
  command = apply

  variables {
    bucket_name = "locked-down-bucket"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "block_public_acls should be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "block_public_policy should be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == true
    error_message = "ignore_public_acls should be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    error_message = "restrict_public_buckets should be true"
  }
}

# ---------------------------------------------------------------------------
# TEST 7: Encryption uses correct algorithm (apply mode)
# ---------------------------------------------------------------------------
# Encryption "rule" is a set-type block in AWS provider, so we use
# for expressions instead of [0] indexing.
# ---------------------------------------------------------------------------
run "encryption_uses_aes256_by_default" {
  command = apply

  variables {
    bucket_name = "encrypted-bucket"
  }

  # Check algorithm using for expression (safe for set-type blocks)
  assert {
    condition = alltrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      alltrue([
        for config in rule.apply_server_side_encryption_by_default :
        config.sse_algorithm == "AES256"
      ])
    ])
    error_message = "Default encryption should be AES256"
  }

  # Check bucket key is enabled
  assert {
    condition = alltrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      rule.bucket_key_enabled == true
    ])
    error_message = "Bucket key should be enabled"
  }
}

# ---------------------------------------------------------------------------
# TEST 8: Tags are applied correctly
# ---------------------------------------------------------------------------
run "tags_applied_to_bucket" {
  command = plan

  variables {
    bucket_name = "tagged-bucket"
    tags = {
      Environment = "test"
      Project     = "learning"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Project"] == "learning"
    error_message = "Project tag should be 'learning'"
  }
}
