# GitOps & 인프라 통합 가이드 (Terraform + OIDC)

이 문서는 `chatda-terraform` 리포지토리의 인프라 코드를 `chatda-cloud-BE` 서버 리포지토리로 통합하고, **장기 자격증명(IAM Access Key) 없이 안전하게 GitHub Actions에서 배포(OIDC)하는 방법**을 안내합니다.

## 1. 개요 및 주요 변경 사항
- **인프라 코드 통합:** 기존 외부 테라폼 코드를 `infra/` 디렉토리로 이동하여 백엔드 애플리케이션과 함께 관리합니다.
- **OIDC (OpenID Connect) 도입:** GitHub Actions가 AWS에 접근할 때 영구적인 IAM Key 대신 임시 토큰(OIDC)을 사용하도록 전환하여 보안을 강화했습니다.
- **역할(Role) 분리:**
  - `github_actions_terraform_role`: 인프라 생성/삭제용 (Terraform 전용, 높은 권한)
  - `github_actions_role`: 서비스 배포용 (ECR 푸시, ECS 업데이트 등 CD 전용, 최소 권한)
- **Free Tier 호환성 (주의):** AWS Free Tier (Academy/Educate) 계정 제한에 걸리지 않도록 RDS 인스턴스는 `db.t3.micro`를 사용하며, `backup_retention_period = 0`으로 설정되어 있습니다. (`infra/main.tf` 참조)

---

## 2. 최초 1회 로컬 부트스트랩 (필수 단계)

OIDC 인증을 사용하려면 AWS에 `GitHub OIDC Provider`와 `IAM Role`이 먼저 생성되어 있어야 합니다. 닭과 달걀의 문제이므로, **최초 1회는 관리자의 로컬 PC에서 임시로 인프라를 배포(Bootstrap)**해야 합니다.

### 부트스트랩 순서
1. **AWS CLI 및 자격 증명 준비**
   로컬 PC에 배포할 대상 AWS 계정의 관리자 권한 자격 증명(Access Key)을 환경 변수로 등록합니다.
   ```bash
   export AWS_ACCESS_KEY_ID="당신의_ACCESS_KEY"
   export AWS_SECRET_ACCESS_KEY="당신의_SECRET_KEY"
   export AWS_DEFAULT_REGION="ap-northeast-2"
   ```

2. **변수 파일 준비**
   `infra/` 디렉토리로 이동한 뒤 `terraform.tfvars.example` 파일을 복사하여 `terraform.tfvars`를 만듭니다.
   ```bash
   cd infra
   cp terraform.tfvars.example terraform.tfvars
   ```
   `terraform.tfvars` 파일을 열고 본인의 GitHub 계정(`github_org`, `github_repo`) 및 DB 비밀번호 등을 상황에 맞게 수정합니다.
   `feature/gitops-terraform` 브랜치에서 GitHub Actions를 실행하려면 `github_branches`에 해당 브랜치가 포함되어 있어야 합니다.

3. **Terraform 초기화 및 적용**
   ```bash
   terraform init
   terraform plan
   terraform apply -auto-approve
   ```

4. **결과(ARN) 기록**
   적용이 완료되면 터미널 출력(Outputs)에 여러 항목이 나옵니다. 이 중 **다음 두 가지 값을 반드시 메모**해 두세요.
   - `github_actions_terraform_role_arn` (예: `arn:aws:iam::123456789012:role/...-terraform-role`)
   - `github_actions_role_arn` (예: `arn:aws:iam::123456789012:role/...-role`)

---

## 3. GitHub Secrets 설정

로컬 부트스트랩이 끝났다면, 이제 GitHub Actions에서 OIDC를 사용할 수 있도록 Secret을 등록해야 합니다. **기존에 저장되어 있던 `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY`는 삭제하세요.**

GitHub 레포지토리의 `Settings` > `Secrets and variables` > `Actions` 로 이동하여 다음 항목들을 등록합니다:

| Secret 이름 | 설명 / 값 |
|---|---|
| `AWS_TERRAFORM_ROLE_ARN` | 부트스트랩 결과로 나온 `github_actions_terraform_role_arn` 값 |
| `AWS_DEPLOY_ROLE_ARN` | 부트스트랩 결과로 나온 `github_actions_role_arn` 값 |
| `TF_VAR_DB_PASSWORD` | 인프라 생성에 사용할 DB 비밀번호 |
| `ECR_REPOSITORY` | Terraform이 생성한 ECR repository 이름. 기본값 기준 `chatda-mvp-fastapi` |
| `ECS_CLUSTER` | Terraform이 생성한 ECS cluster 이름. 기본값 기준 `chatda-mvp-cluster` |
| `ECS_SERVICE` | Terraform이 생성한 ECS service 이름. 기본값 기준 `chatda-mvp-fastapi` |
| `ECS_TASK_DEFINITION` | Terraform이 생성한 ECS task definition family. 기본값 기준 `chatda-mvp-fastapi` |
| `CONTAINER_NAME` | Task definition의 container 이름. 기본값 기준 `fastapi` |
| `LAMBDA_FUNCTION_NAME` | Terraform이 생성한 Lambda 함수 이름. 기본값 기준 `chatda-mvp-presigned-url` |

---

## 4. CI/CD 워크플로우 사용법

### Terraform 워크플로우 (`terraform.yml`)
- **자동 Plan:** `feature/gitops-terraform` 브랜치에서 `infra/` 또는 Terraform workflow 파일이 수정되어 push되면 `terraform plan` 까지만 자동으로 실행됩니다.
- **수동 Apply/Destroy:** GitHub Actions 탭에서 `Terraform` 워크플로우를 선택하고 **Run workflow** 버튼으로 `apply` 또는 `destroy`를 실행합니다. OIDC role의 허용 브랜치(`github_branches`)에 현재 브랜치가 포함되어 있어야 합니다.

### 배포 워크플로우 (`deploy-ecs.yml`, `deploy-lambda.yml`)
- 기존과 동일하게 `main` 또는 `develop` 브랜치에 코드가 푸시되면 자동으로 빌드 후 배포됩니다.
- `feature/gitops-terraform` 브랜치에서는 GitHub Actions의 `Deploy to ECS` 워크플로우를 **Run workflow**로 직접 실행해 첫 FastAPI Docker image를 ECR에 push할 수 있습니다.
- 내부적으로 위에서 등록한 `AWS_DEPLOY_ROLE_ARN` 토큰을 사용하여 안전하게 배포됩니다.
- ECS는 ARM64 멀티플랫폼 빌드를 적용하도록 구성되어 있습니다.
- Terraform은 인프라 생성을 담당하고, ECS 앱 이미지 롤아웃은 `deploy-ecs.yml`이 담당합니다. 그래서 `aws_ecs_service`는 배포 워크플로우가 갱신한 task definition을 Terraform apply 때 되돌리지 않도록 설정되어 있습니다.
