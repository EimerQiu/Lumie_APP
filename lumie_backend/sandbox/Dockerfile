FROM python:3.11-slim

RUN pip install --no-cache-dir \
    pymongo==4.7.0 \
    pandas==2.2.0 \
    matplotlib==3.9.0 \
    numpy==1.26.0

RUN adduser --disabled-password --no-create-home sandbox

RUN mkdir -p /app /output && chown sandbox:sandbox /output

WORKDIR /app

USER sandbox

CMD ["python", "main.py"]
