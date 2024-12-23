# SET UP upload-files-app
- Replace the env variable

# SET UP upload-files-be
- Create the sercet by run the script following
 kubectl create secret generic gac-keys --from-file=<PATH_TO_SERVICE_ACCOUNT_FILE>

 example: kubectl create secret generic gac-keys --from-file=valiant-hexagon-443709-r2-361570097b8d.json

 - Replace the value of GOOGLE_APPLICATION_CREDENTIALS environment variable by your filename. (Example: valiant-hexagon-443709-r2-361570097b8d.json)
  