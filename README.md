# Terraform Unit Testing Demo

This repo demonstrates **Terraform native tests** (`terraform test`) — a built-in testing framework available since Terraform 1.6.

## Why Unit Test Terraform?

| Without tests | With tests |
|---|---|
| "It worked last time" | Automated proof that modules behave correctly |
| Bugs found during `terraform apply` in production | Bugs caught in CI before merge |
| Manual review is the only safety net | Assertions enforce your security/compliance rules |

## What's Inside

```
s3-bucket/
├── main.tf                        # S3 bucket module (bucket, versioning, encryption, public access block)
├── variables.tf                   # Input variables with validation rules
├── outputs.tf                     # Module outputs
├── versions.tf                    # Terraform & provider version constraints
└── tests/
    └── s3_bucket.tftest.hcl       # 8 native Terraform tests
```

## How Terraform Tests Work

### Key Concepts

1. **Test files** live in a `tests/` directory and use the `.tftest.hcl` extension.
2. Each file contains one or more `run` blocks — each block is an individual test case.
3. Tests use `assert` blocks with a `condition` and `error_message`.
4. Tests can run in **plan** mode (fast, no resources created) or **apply** mode (simulates full creation).
5. **Mock providers** (`mock_provider "aws" {}`) simulate cloud APIs — **no credentials needed, zero cost**.

### The Test File Anatomy

```hcl
# Declare a mock provider — no real AWS calls
mock_provider "aws" {}

# A single test case
run "descriptive_test_name" {
  command = plan          # or apply

  variables {
    bucket_name = "my-bucket"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "my-bucket"
    error_message = "Bucket name should match input"
  }
}
```

### What Each Test Covers

| # | Test Name | Mode | What It Verifies |
|---|-----------|------|-----------------|
| 1 | `bucket_name_matches_input` | plan | Bucket name matches the variable passed in |
| 2 | `rejects_short_bucket_name` | plan | Validation rejects names shorter than 3 chars |
| 3 | `rejects_invalid_sse_algorithm` | plan | Validation rejects unsupported encryption algorithms |
| 4 | `versioning_enabled_by_default` | plan | Versioning defaults to "Enabled" |
| 5 | `versioning_can_be_disabled` | plan | Versioning can be explicitly set to "Suspended" |
| 6 | `public_access_fully_blocked` | apply | All 4 public access block settings are `true` |
| 7 | `encryption_uses_aes256_by_default` | apply | Default SSE algorithm is AES256 with bucket key enabled |
| 8 | `tags_applied_to_bucket` | apply | Tags passed as input appear on the bucket resource |

### plan vs apply Mode

- **`command = plan`** — Runs `terraform plan` only. Fast. Good for checking input-derived values and variable validations.
- **`command = apply`** — Simulates resource creation (using mocks). Needed when testing computed values or set-type attribute blocks.

### `expect_failures` — Testing That Things Should Fail

```hcl
run "rejects_short_bucket_name" {
  command = plan
  variables { bucket_name = "ab" }

  # Inverted logic: if validation PASSES, the test FAILS
  expect_failures = [ var.bucket_name ]
}
```

## Running Tests Locally

```bash
cd s3-bucket

# Initialize providers (only needed once)
terraform init

# Run all tests
terraform test

# Run tests with verbose output
terraform test -verbose
```

### Expected Output

```
$ terraform test
tests/s3_bucket.tftest.hcl... in progress
  run "bucket_name_matches_input"...        pass
  run "rejects_short_bucket_name"...        pass
  run "rejects_invalid_sse_algorithm"...    pass
  run "versioning_enabled_by_default"...    pass
  run "versioning_can_be_disabled"...       pass
  run "public_access_fully_blocked"...      pass
  run "encryption_uses_aes256_by_default".. pass
  run "tags_applied_to_bucket"...           pass
tests/s3_bucket.tftest.hcl... tearing down
tests/s3_bucket.tftest.hcl... pass

Success! 8 passed, 0 failed.
```

## CI/CD

Tests run automatically on every push and pull request via GitHub Actions. See [.github/workflows/terraform-test.yml](.github/workflows/terraform-test.yml).

The workflow:
1. **Format Check** — `terraform fmt -check` ensures consistent code style
2. **Validate** — `terraform validate` checks HCL syntax
3. **Test** — `terraform test` runs all unit tests

No AWS credentials are needed in CI because mock providers handle everything.

## Requirements

- Terraform >= 1.9 (this module uses `>= 1.9` in `versions.tf`)
- No AWS credentials needed (tests use mock providers)
