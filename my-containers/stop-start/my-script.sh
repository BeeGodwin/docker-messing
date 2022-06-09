FILE=./hello-world

if [ ! -f "$FILE" ]; then
  echo "create file"
  touch hello-world
else
  echo "file exists"
fi