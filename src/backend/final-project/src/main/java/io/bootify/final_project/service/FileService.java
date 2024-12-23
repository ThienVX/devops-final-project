package io.bootify.final_project.service;

import io.bootify.final_project.DTO.FileDto;
import io.bootify.final_project.entity.InputFile;
import io.bootify.final_project.utils.UploadGcpBucketUtil;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

@Service
@RequiredArgsConstructor
public class FileService implements IFileService{

    private static final Logger LOGGER = LoggerFactory.getLogger(FileService.class);

    private final UploadGcpBucketUtil dataBucketUtil;

    @Override
    public List<InputFile> uploadFiles(MultipartFile[] files) {

        LOGGER.debug("Start file uploading service");
        List<InputFile> inputFiles = new ArrayList<>();

        Arrays.asList(files).forEach(file -> {
            String originalFileName = file.getOriginalFilename();
            if(originalFileName == null){
                throw new RuntimeException("Original file name is null");
            }
            Path path = new File(originalFileName).toPath();

            try {
                String contentType = Files.probeContentType(path);
                FileDto fileDto = dataBucketUtil.uploadFile(file, originalFileName, contentType);

                if (fileDto != null) {
                    LOGGER.debug("File uploaded successfully, file name: {} and url: {}",fileDto.getFileName(), fileDto.getFileUrl() );
                    inputFiles.add(new InputFile(fileDto.getFileName(),fileDto.getFileUrl() ));
                }
            } catch (Exception e) {
                LOGGER.error("Error occurred while uploading. Error: ", e);
                throw new RuntimeException("Error occurred while uploading");
            }
        });

        LOGGER.debug("File details successfully saved in the database");
        return inputFiles;
    }
}
