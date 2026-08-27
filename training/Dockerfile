FROM python:3.11-slim

# SageMaker BYOC containers should not buffer stdout - training logs need to
# stream to CloudWatch in real time, not batch at process exit.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /opt/ml/code

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY train.py .

# SageMaker's training contract: `docker run <image> train` is the standard
# invocation - "train" arrives as a runtime argument. We satisfy the contract
# by having a `train` executable on PATH, but deliberately DO NOT forward that
# argument to train.py - our script takes no positional args, and forwarding
# it caused argparse to fail with "unrecognized arguments: train" (exit code 2).
RUN printf '#!/bin/bash\nset -e\npython3 /opt/ml/code/train.py\n' > /usr/local/bin/train \
    && chmod +x /usr/local/bin/train

ENTRYPOINT ["train"]