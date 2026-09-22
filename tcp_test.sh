timeout 8 bash -c "cat < /dev/null > /dev/tcp/ep-jolly-fog-b32uc493-pooler.c-4.ap-southeast-1.aws.neon.tech/5432" && echo CONNECTED || echo FAILED
