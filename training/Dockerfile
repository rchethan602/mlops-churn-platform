FROM python:3.11-slim

# SageMaker BYOC containers should not buffer stdout - training logs need to
# stream to CloudWatch in real time, not batch at process exit.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /opt/ml/code

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY train.py .

# SageMaker's training toolkit contract: `docker run <image> train` is the
# standard invocation. We satisfy this by placing an executable named `train`
# on PATH that runs our script - this way the container works whether
# SageMaker (or a human debugging locally) invokes it with or without args.
RUN printf '#!/bin/bash\nset -e\npython3 /opt/ml/code/train.py "$@"\n' > /usr/local/bin/train \
    && chmod +x /usr/local/bin/train

ENTRYPOINT ["train"]