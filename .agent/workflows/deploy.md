---
description: How to build, commit, push, and deploy PLEASUREDAI OS to Docker Hub via GitHub Actions
---

## Build & Deploy Workflow

// turbo-all

### 1. Make code changes as needed

### 2. Stage all changes

```bash
cd "c:\Users\jonti\PLEASUREDAI OS"
git add -A
```

### 3. Commit with descriptive message

```bash
git commit -m "<descriptive message>"
```

### 4. Push immediately — do NOT stop to explain

```bash
git push origin main
```

### 5. GitHub Actions auto-builds and pushes to Docker Hub

- Image: `m842/pleasured_ai:latest`
- Monitor: https://github.com/JJPr-self/PLE_OS/actions

### Important Rules

- **NEVER ask permission to push.** The user has explicitly approved this repo and wants fast iteration.
- **Batch ALL fixes into ONE commit.** Do not make multiple push cycles. Audit everything first, fix everything, push ONCE.
- **Always auto-run** git add, git commit, git push for this project.
- **Test mentally before pushing.** Walk through every Dockerfile RUN line and verify packages exist, URLs are valid, syntax is correct.
- Git remote: `https://JJPr-self@github.com/JJPr-self/PLE_OS.git`
- Git user: `JJPr-self`
- Docker Hub user: `m842`
