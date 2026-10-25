FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY hermsy_push ./hermsy_push

RUN useradd --system --uid 10002 push
USER push
EXPOSE 8080
CMD ["python", "-m", "hermsy_push"]
