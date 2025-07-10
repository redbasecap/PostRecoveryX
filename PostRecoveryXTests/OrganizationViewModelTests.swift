import Testing
import Foundation
@testable import PostRecoveryX

struct OrganizationViewModelTests {
    
    @Test func getRenamedFileNameWithDate() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setRenameFilesWithDate(true)
        
        let testDate = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 15))!
        
        let file = ScannedFile(path: "/test/path/image.jpg")
        file.originalCreationDate = testDate
        file.fileName = "image.jpg"
        
        let renamedName = await viewModel.testGetRenamedFileName(for: file)
        
        #expect(renamedName == "2024-03-15_image.jpg")
    }
    
    @Test func getRenamedFileNameWithoutExtension() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setRenameFilesWithDate(true)
        
        let testDate = Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 25))!
        
        let file = ScannedFile(path: "/test/path/document")
        file.originalCreationDate = testDate
        file.fileName = "document"
        
        let renamedName = await viewModel.testGetRenamedFileName(for: file)
        
        #expect(renamedName == "2023-12-25_document")
    }
    
    @Test func getRenamedFileNameFallsBackToOriginalWithoutDate() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setRenameFilesWithDate(true)
        
        let file = ScannedFile(path: "/test/path/nodate.png")
        file.fileName = "nodate.png"
        
        let renamedName = await viewModel.testGetRenamedFileName(for: file)
        
        #expect(renamedName == "nodate.png")
    }
    
    @Test func organizationTasksWithRenaming() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setRenameFilesWithDate(true)
        
        let testDate = Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 10))!
        
        let file = ScannedFile(path: "/test/vacation.jpg")
        file.originalCreationDate = testDate
        file.fileName = "vacation.jpg"
        file.isProcessed = true
        
        let expectedFileName = "2024-06-10_vacation.jpg"
        
        #expect(viewModel.renameFilesWithDate == true)
    }
    
    @Test func organizationTasksWithoutRenaming() async {
        let viewModel = await OrganizationViewModel()
        await viewModel.setRenameFilesWithDate(false)
        
        let file = ScannedFile(path: "/test/photo.jpg")
        file.fileName = "photo.jpg"
        file.isProcessed = true
        
        #expect(viewModel.renameFilesWithDate == false)
    }
}

extension OrganizationViewModel {
    func setRenameFilesWithDate(_ value: Bool) {
        self.renameFilesWithDate = value
    }
    
    func testGetRenamedFileName(for file: ScannedFile) -> String {
        return getRenamedFileName(for: file)
    }
}