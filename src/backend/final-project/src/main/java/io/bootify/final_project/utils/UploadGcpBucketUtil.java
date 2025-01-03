package io.bootify.final_project.utils;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.Blob;
import com.google.cloud.storage.Bucket;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import io.bootify.final_project.DTO.FileDto;
import org.apache.commons.io.FileUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.UUID;

@Component
public class UploadGcpBucketUtil {
    private static final Logger LOGGER = LoggerFactory.getLogger(UploadGcpBucketUtil.class);

    @Value("${gcp.config.file}")
    private String gcpConfigFile;

    @Value("${gcp.project.id}")
    private String gcpProjectId;

    @Value("${gcp.bucket.id}")
    private String gcpBucketId;

    @Value("${gcp.dir.name}")
    private String gcpDirectoryName;


    public FileDto uploadFile(MultipartFile multipartFile, String fileName, String contentType) throws Exception {

        try{

            LOGGER.debug("Start file uploading process on GCS");
            byte[] fileData = FileUtils.readFileToByteArray(convertFile(multipartFile));
//            LOGGER.info("Dir ls " +  System.getProperty("user.dir"));
//            LOGGER.info("Start file uploading process on GCS " + new ClassPathResource(gcpConfigFile).exists());

//            InputStream inputStream = new ClassPathResource(gcpConfigFile).getInputStream();

            StorageOptions options = StorageOptions.newBuilder().setProjectId(gcpProjectId)
//                    .setCredentials(GoogleCredentials.fromStream(inputStream))
                    .build();

            Storage storage = options.getService();
            Bucket bucket = storage.get(gcpBucketId,Storage.BucketGetOption.fields());

//            RandomString id = new RandomString(6, ThreadLocalRandom.current());
            String id = UUID.randomUUID().toString().replace("-", "");
            Blob blob = bucket.create(gcpDirectoryName + "/" + fileName + "-" + id + checkFileExtension(fileName), fileData, contentType);

            if(blob != null){
                LOGGER.debug("File successfully uploaded to GCS");
                return new FileDto(blob.getName(), blob.getMediaLink());
            }

        }catch (Exception e){
            LOGGER.error("An error occurred while uploading data. Exception: ", e);
            throw new Exception("An error occurred while storing data to GCS");
        }
        throw new Exception("An error occurred while storing data to GCS");
    }

    private File convertFile(MultipartFile file) throws Exception {

        try{
            if(file.getOriginalFilename() == null){
                throw new Exception("Original file name is null");
            }
            File convertedFile = new File(file.getOriginalFilename());
            FileOutputStream outputStream = new FileOutputStream(convertedFile);
            outputStream.write(file.getBytes());
            outputStream.close();
            LOGGER.debug("Converting multipart file : {}", convertedFile);
            return convertedFile;
        }catch (Exception e){
            throw new Exception("An error has occurred while converting the file");
        }
    }

    private String checkFileExtension(String fileName) throws Exception {
        if(fileName != null && fileName.contains(".")){
            String[] extensionList = {".png", ".jpeg", ".pdf", ".doc", ".mp3"};

            for(String extension: extensionList) {
                if (fileName.endsWith(extension)) {
                    LOGGER.debug("Accepted file type : {}", extension);
                    return extension;
                }
            }
        }
        LOGGER.error("Not a permitted file type");
        throw new Exception("Not a permitted file type");
    }
}
