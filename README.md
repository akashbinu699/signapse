# AI Infrastructure Engineering Technical Test

## Objective
You will take a simple local diffusion model and deploy it as a scalable inference service on **AWS SageMaker** using a custom Docker container.

This exercise evaluates:
- ML engineering instincts
- GPU optimisation
- Software engineering quality
- Infrastructure & cloud skills
- Ability to improve existing (poor) code

Signapse belives strongly in using the best tools for the job. In the spirit of that belief, we are happy for you to use AI where appropriate. 

## Tasks

### 1. Run the Model Locally
You are provided with deliberately unoptimised Python code in src/.
Your first task is simply to run it and understand its behaviour.

Example:

``
python src/app.py --prompt "a futuristic city floating in the clouds"
``

### 2. Optimise the Model Code
The provided code is intentionally slow and inefficient.

You should:

#### Fix and improve the inference pipeline
- Move model loading out of the request path
- Add model warmup
- Use torch.inference_mode()
- Use torch.autocast("cuda") for mixed precision
- Remove unnecessary CUDA synchronisation
- Reduce GPU memory footprint
- Consider enabling attention/vae slicing or offloading
- Improve output encoding performance
- Improve code structure and readability

#### Optional (but rewarded):
- Add batching support
- Add caching for repeated prompts
- Reduce inference steps / convert to JPEG for performance
- Add meaningful logging

Please document the optimisations you apply.

### 3. Containerize the Model
- Inspect the provided docker/Dockerfile (also intentionally inefficient).
- Improve it if necessary (layer reduction, smaller CUDA image, version pinning, etc.).
- Build and run the model container locally.
- Ensure the /predict endpoint works inside the container.

### 4. Deploy on AWS SageMaker
You must:
- Create a CI pipeline that will build & push your Docker image to Amazon ECR
- Create a Terraform script that will deploy the image to AWS SageMaker Inference and expose a /predict endpoint
- Write tests using Terratest or similar to ensure the deployment works as expected

You may use:
- AWS CLI
- Terraform
- AWS SageMaker Python SDK

## Stretch Goals (Optional)
These are not required but will positively influence evaluation:
- Autoscaling policies
- GPU utilisation monitoring
- S3 output storage + presigned URLs
- CI/CD pipeline for container build & deploy (GitHub Actions)
- Multi-model or multi-container serving design
- Batch or asynchronous inference support

## Deliverables
You must provide:

#### 1. A GitHub repository containing:
- Improved and refactored source code
- Optimised Dockerfile
- Deployment scripts (bash / Python / IaC)
- Any utility scripts you use
- A README explaining:
  - How to build the image
  - How to deploy the image
  - The optimisations you implemented
  - How to call the endpoint

#### 2. Clear documentation explaining how to deploy your infrastructure and a working test case.

## What We Evaluate
#### ML Systems Engineering
- GPU memory management
- Torch optimisations (autocast, inference mode, etc.)

#### Infrastructure & DevOps
- Docker optimisation
- SageMaker architecture knowledge
- Use of AWS services responsibly and cost-effectively

#### Software Engineering
- Code refactoring and clarity
- Modularity and maintainability
- Error handling and logging

#### Performance Improvements
- Reduction in loading time
- Reduction in inference latency
- Reduced GPU memory usage
- Observed speedup after your changes

### Good luck 🚀

We are evaluating your ability to improve, deploy, and operate AI systems — not just make something “work”, but make it production-ready.