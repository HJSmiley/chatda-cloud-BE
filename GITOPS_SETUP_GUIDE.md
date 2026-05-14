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
   `terraform.tfvars` 파일을 열고 GitHub Actions를 실제로 실행할 저장소와 정확히 같은 owner/repo(`github_org`, `github_repo`) 및 DB 비밀번호 등을 상황에 맞게 수정합니다.
   예를 들어 fork인 `https://github.com/HJSmiley/chatda-cloud-BE.git`에서 먼저 테스트한다면 `github_org = "HJSmiley"`, `github_repo = "chatda-cloud-BE"`여야 합니다. 반대로 원본 `https://github.com/chatda-cloud/chatda-cloud-BE.git`에서 Actions를 실행한다면 `github_org = "chatda-cloud"`로 apply해야 합니다. OIDC subject는 owner/repo까지 정확히 일치해야 하므로 다른 owner로 만든 role ARN을 Secret에 넣으면 AWS가 AssumeRole을 거부합니다.
   `develop`, `main`, `feature/gitops-terraform`처럼 GitHub Actions를 실행할 브랜치는 모두 `github_branches`에 포함되어 있어야 합니다.

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

   `github_actions_oidc_subjects`에는 GitHub Actions OIDC trust policy가 허용하는 브랜치 subject가 출력됩니다. `develop` 배포를 허용하려면 `repo:<OWNER>/<REPO>:ref:refs/heads/develop` 값이 포함되어 있어야 합니다.

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
- **자동 Plan:** `develop`, `main`, `feature/gitops-terraform` 브랜치에서 `infra/` 또는 Terraform workflow 파일이 수정되어 push되면 `terraform plan` 까지만 자동으로 실행됩니다.
- **수동 Apply/Destroy:** GitHub Actions 탭에서 `Terraform` 워크플로우를 선택하고 **Run workflow** 버튼으로 `apply` 또는 `destroy`를 실행합니다. OIDC role의 허용 브랜치(`github_branches`)에 현재 브랜치가 포함되어 있어야 합니다.

> `deploy-ecs.yml`이 `Not authorized to perform sts:AssumeRoleWithWebIdentity`로 실패하면 ECR/ECS 권한 문제가 아니라 IAM Role의 trust policy가 현재 브랜치 subject를 거부한 것입니다. 이 경우 관리자 권한이 있는 로컬 환경에서 `terraform apply`를 한 번 실행해 `github_branches` 변경을 AWS IAM Role에 반영한 뒤 다시 배포 워크플로우를 실행하세요. GitHub Actions는 OIDC trust가 막힌 상태에서는 스스로 이 trust policy를 고칠 수 없습니다.

> `terraform apply` 중 `You can't create this secret because a secret with this name is already scheduled for deletion` 오류가 나면, 같은 이름의 Secrets Manager secret이 삭제 예약 상태라서 재생성이 막힌 것입니다. 현재 Terraform 코드는 이 충돌을 피하기 위해 `chatda-mvp/db/password-<suffix>` 형태의 고유한 secret 이름을 사용합니다. 그래도 고정 이름을 쓰던 과거 state로 apply 중이라면 먼저 삭제 예약을 취소한 뒤 다시 apply하세요.
> ```bash
> aws secretsmanager restore-secret \
>   --secret-id chatda-mvp/db/password \
>   --region ap-northeast-2
> ```
> Terraform state에 secret이 없다는 import 안내가 나오면 아래처럼 기존 secret을 state에 연결한 뒤 다시 apply합니다.
> ```bash
> terraform import aws_secretsmanager_secret.db_password chatda-mvp/db/password
> terraform apply
> ```

### Fork에서 먼저 검증하고 원본 레포로 옮기는 경우
1. fork 저장소(`HJSmiley/chatda-cloud-BE`)에서 테스트할 때는 로컬 `terraform.tfvars`의 `github_org`를 `HJSmiley`로 두고 `terraform apply`를 실행합니다.
2. 출력된 `github_actions_terraform_role_arn`, `github_actions_role_arn` 값을 fork 저장소의 GitHub Actions Secret에 등록합니다.
3. fork의 `feature/gitops-terraform` 브랜치에 push하여 Terraform 워크플로우를 먼저 통과시킨 뒤, `develop`으로 머지합니다.
4. `deploy-lambda.yml`, `deploy-ecs.yml`, `ci.yml`까지 통과하면 같은 파일들을 원본 저장소 작업환경에 반영해 PR을 올립니다.
5. 원본 저장소에서 Actions를 직접 실행하려면, 원본 저장소 기준으로 다시 `github_org = "chatda-cloud"`를 적용한 IAM Role ARN을 원본 저장소 Secret에 등록해야 합니다.

### 배포 워크플로우 (`deploy-ecs.yml`, `deploy-lambda.yml`)
- 기존과 동일하게 `main` 또는 `develop` 브랜치에 코드가 푸시되면 자동으로 빌드 후 배포됩니다.
- `feature/gitops-terraform` 브랜치에서는 GitHub Actions의 `Deploy to ECS` 워크플로우를 **Run workflow**로 직접 실행해 첫 FastAPI Docker image를 ECR에 push할 수 있습니다.
- 내부적으로 위에서 등록한 `AWS_DEPLOY_ROLE_ARN` 토큰을 사용하여 안전하게 배포됩니다.
- ECS는 ARM64 멀티플랫폼 빌드를 적용하도록 구성되어 있습니다.
- Terraform은 인프라 생성을 담당하고, ECS 앱 이미지 롤아웃은 `deploy-ecs.yml`이 담당합니다. 그래서 `aws_ecs_service`는 배포 워크플로우가 갱신한 task definition을 Terraform apply 때 되돌리지 않도록 설정되어 있습니다.
