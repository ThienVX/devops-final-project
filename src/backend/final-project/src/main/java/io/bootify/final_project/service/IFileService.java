package io.bootify.final_project.service;

import io.bootify.final_project.entity.InputFile;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

public interface IFileService {
    List<InputFile> uploadFiles(MultipartFile[] files);
}
