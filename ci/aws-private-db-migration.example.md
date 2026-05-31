# Example: GitHub-triggered DB migration inside AWS private network

This is a reference example showing how to run production database migrations when the database is only reachable from AWS private networking (VPN/VPC).

## 1) GitHub Actions workflow (orchestrator only)

```yaml
name: prod-migrate-example

on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: "Release tag to deploy (for example v1.8.2)"
        required: true
        type: string

permissions:
  id-token: write
  contents: read

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/github-actions-prod-deployer
          aws-region: ap-southeast-2

      - name: Start migration build
        id: start
        run: |
          BUILD_ID=$(aws codebuild start-build \
            --project-name prod-db-migrations \
            --environment-variables-override \
              name=RELEASE_TAG,value=${{ inputs.release_tag }},type=PLAINTEXT \
            --query 'build.id' --output text)
          echo "build_id=$BUILD_ID" >> "$GITHUB_OUTPUT"

      - name: Wait for migration result
        run: |
          aws codebuild wait build-succeeded --ids "${{ steps.start.outputs.build_id }}"
```

## 2) CodeBuild buildspec (runs inside VPC)

```yaml
version: 0.2
phases:
  install:
    commands:
      - npm ci
  build:
    commands:
      - npx prisma migrate deploy --schema prisma/appdb/schema.prisma
```

## 3) IAM trust policy (OIDC role for GitHub Actions)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:seain-malkin/temp-servoy-test:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

## Notes

- Keep GitHub Actions as the trigger/orchestrator; execute migrations in AWS private networking.
- Attach the CodeBuild project to the VPC/subnets/security groups that can reach the database.
- Use short-lived AWS credentials (OIDC) and avoid long-lived static secrets.
- Add a deployment gate so app rollout only proceeds after migration job success.
