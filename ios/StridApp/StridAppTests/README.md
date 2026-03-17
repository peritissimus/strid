# StridApp Test Suite

Comprehensive automated tests for StridApp iOS/macOS PII Scanner.

## Quick Start

### 1. Set Up Test Targets in Xcode

**Create iOS Test Target:**
1. Open `StridApp.xcodeproj` in Xcode
2. File → New → Target
3. Choose "Unit Testing Bundle"
4. Name: `StridAppTests`
5. Platform: iOS
6. Host Application: `StridApp_iOS`
7. Enable "Allow testing Host Application APIs"
8. Click "Finish"

**Create macOS Test Target:**
1. File → New → Target
2. Choose "Unit Testing Bundle"
3. Name: `StridAppMacTests`
4. Platform: macOS
5. Host Application: `StridApp_macOS`
6. Enable "Allow testing Host Application APIs"
7. Click "Finish"

### 2. Add Test Files to Targets

1. In Xcode's Project Navigator, locate the `StridAppTests` folder
2. Select all files in the `Helpers` and `Unit` directories
3. Right-click → Add Files to "StridAppTests"
4. Ensure both `StridAppTests` and `StridAppMacTests` targets are checked
5. Click "Add"

### 3. Link StridKit Package

1. Select the `StridAppTests` target
2. General → Frameworks and Libraries
3. Click "+" → Add "StridKit" package
4. Repeat for `StridAppMacTests` target

### 4. Run Tests

**In Xcode:**
- Press `Cmd+U` to run all tests
- Or: Cmd+6 (Test Navigator) → Click ▶ next to test target

**Command Line:**
```bash
# iOS tests
xcodebuild test \
  -scheme StridApp_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# macOS tests
xcodebuild test \
  -scheme StridApp_macOS \
  -destination 'platform=macOS'
```

## Test Structure

```
StridAppTests/
  ├── Helpers/
  │   ├── TestFactories.swift      # Factory methods for test data
  │   ├── MockDependencies.swift   # Mock implementations of ports
  │   └── MockDIContainer.swift    # Test DI container
  ├── Unit/
  │   ├── ViewModels/
  │   │   └── DocumentListViewModelTests.swift  # Sample tests (ready!)
  │   ├── UseCases/                 # TODO: Add use case tests
  │   ├── Repositories/             # TODO: Add repository tests
  │   └── Adapters/                 # TODO: Add adapter tests
  └── Integration/                  # TODO: Add integration tests
```

## Test Utilities

### TestFactories

Create test data easily:

```swift
// Create a document
let doc = TestFactories.makeDocument(content: "Test content")

// Create detected PII
let email = TestFactories.makeDetectedPII(type: .email, text: "test@example.com")

// Create scanned document
let scannedDoc = TestFactories.makeScannedDocument(
    content: "Email: test@example.com",
    source: .clipboard,
    entityCount: 1
)

// Use sample documents
let indianPII = TestFactories.sampleIndianPIIDocument
```

### MockDependencies

Use configurable mocks:

```swift
// Configure mock detector
let mockDetector = MockPIIDetector()
mockDetector.configureToDetectEmail("test@example.com")

// Use mock repository
let mockRepo = MockScannedDocumentRepository()
await mockRepo.save(document)
let count = await mockRepo.saveCallCount // Track interactions
```

### MockDIContainer

Wire up dependencies for tests:

```swift
// Create container with mocks
let container = MockDIContainer()

// Configure for common scenarios
container.configureForEmailDetection()
container.configureForMultiPIIDetection()

// Pre-populate with test data
try await container.populateWithTestDocuments(count: 5)

// Create ViewModels with mocks injected
let viewModel = container.makeDocumentListViewModel()
```

## Example Test

```swift
import Testing
@testable import StridApp

@Suite("My Test Suite")
@MainActor
struct MyTests {

    @Test("Description of what this tests")
    func myTestFunction() async throws {
        // Given - Set up test data
        let container = MockDIContainer()
        container.configureForEmailDetection()
        let viewModel = container.makeDocumentListViewModel()

        // When - Perform action
        await viewModel.createNewDocument(
            content: "Email: test@example.com",
            source: .clipboard
        )

        // Then - Verify outcome
        await viewModel.loadDocuments()
        #expect(!viewModel.isEmpty)
        #expect(viewModel.scannedDocuments.count == 1)
    }
}
```

## Writing New Tests

### 1. Unit Tests (Priority 1)

Test individual components in isolation:

- **ViewModels**: State management, business logic
- **Use Cases**: Pure business logic, no dependencies on UI
- **Repositories**: Data persistence and retrieval
- **Adapters**: Integration with external services

### 2. Integration Tests (Priority 2)

Test complete workflows:

- Import → Scan → Save → Export
- Document persistence across app restarts
- Concurrent operations

### 3. UI Tests (Priority 3)

Test platform-specific rendering (requires separate UI test target):

- Platform-specific views (iOS vs macOS)
- Snapshot testing for visual regression

## Coverage Goals

| Component | Target | Priority |
|-----------|--------|----------|
| ViewModels | 90% | ⭐ Critical |
| Use Cases | 100% | ⭐ Critical |
| Repositories | 85% | High |
| Adapters | 80% | High |

## Viewing Code Coverage

1. Product → Scheme → Edit Scheme
2. Test → Options
3. Enable "Code Coverage"
4. Run tests (Cmd+U)
5. Report Navigator (Cmd+9) → Coverage tab

## Next Steps

1. ✅ Set up test targets (follow instructions above)
2. ✅ Add test files to targets
3. ✅ Run `DocumentListViewModelTests` to verify setup
4. 🔲 Add more ViewModel tests
5. 🔲 Add Use Case tests
6. 🔲 Add Repository tests
7. 🔲 Add Integration tests

## Troubleshooting

**"No such module 'StridApp'" error:**
- Ensure test target has "Allow testing Host Application APIs" enabled
- Check that StridApp is in target dependencies

**Tests not appearing:**
- Ensure test files are added to test target (not app target)
- Check file's Target Membership in File Inspector

**Async test failures:**
- Add `@MainActor` to test suite for UI-related tests
- Use `await` for async operations

## Resources

- [Swift Testing Guide](https://developer.apple.com/documentation/testing)
- [Testing plan](/Users/peritissimus/.claude/plans/radiant-weaving-spark.md)
- StridKit tests: `/Users/peritissimus/projects/strid/ios/StridKit/Tests/`
