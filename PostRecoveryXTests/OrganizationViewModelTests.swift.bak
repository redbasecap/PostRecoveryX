import Testing
import Foundation
@testable import PostRecoveryX

struct OrganizationViewModelTests {
    
    @Test func getRenamedFileNameWithDate() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setFileNamingMode(.datePrefix)
        
        let testDate = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 15))!
        
        let file = ScannedFile(path: "/test/path/image.jpg", fileName: "image.jpg", fileSize: 1024, fileType: "jpg")
        file.originalCreationDate = testDate
        
        let renamedName = await viewModel.testGetFileName(for: file)
        
        #expect(renamedName.contains("2024-03-15"))
    }
    
    @Test func getRenamedFileNameWithoutExtension() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setFileNamingMode(.datePrefix)
        
        let testDate = Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 25))!
        
        let file = ScannedFile(path: "/test/path/document", fileName: "document", fileSize: 1024, fileType: "")
        file.originalCreationDate = testDate
        
        let renamedName = await viewModel.testGetFileName(for: file)
        
        #expect(renamedName.contains("2023-12-25"))
    }
    
    @Test func getRenamedFileNameFallsBackToOriginalWithoutDate() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setFileNamingMode(.datePrefix)
        
        let file = ScannedFile(path: "/test/path/nodate.png", fileName: "nodate.png", fileSize: 1024, fileType: "png")
        
        let renamedName = await viewModel.testGetFileName(for: file)
        
        #expect(renamedName == "nodate.png")
    }
    
    @Test func organizationTasksWithRenaming() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setFileNamingMode(.datePrefix)
        
        let testDate = Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 10))!
        
        let file = ScannedFile(path: "/test/vacation.jpg", fileName: "vacation.jpg", fileSize: 1024, fileType: "jpg")
        file.originalCreationDate = testDate
        file.isProcessed = true
        
        let expectedFileName = "2024-06-10_vacation.jpg"
        
        #expect(viewModel.fileNamingMode == .datePrefix)
    }
    
    @Test func organizationTasksWithoutRenaming() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setFileNamingMode(.keepOriginal)
        
        let file = ScannedFile(path: "/test/photo.jpg", fileName: "photo.jpg", fileSize: 1024, fileType: "jpg")
        file.isProcessed = true
        
        #expect(viewModel.fileNamingMode == .keepOriginal)
    }
}

extension OrganizationViewModel {
    func setFileNamingMode(_ mode: FileNamingMode) {
        self.fileNamingMode = mode
    }
    
    func testGetFileName(for file: ScannedFile) -> String {
        return getFileName(for: file)
    }
}