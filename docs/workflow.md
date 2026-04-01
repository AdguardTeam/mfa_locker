# MFA Demo - Development Workflow

> **Current Status:** Phase 1 Complete ✅ | Phase 2 Ready 🚀  
> **Next:** Iteration 8 - Biometric Constants & Dependencies

---

## 🎯 Core Principles

1. **KISS** - Simplest solution that works. No overengineering.
2. **Follow the Plan** - `tasklist.md` iterations in exact order. No skipping.
3. **Propose First** - Always get approval before implementing.
4. **Update Progress** - Mark completed tasks immediately.

---

## 🔄 Iteration Workflow (MANDATORY)

### **Step 1: PROPOSE Solution**
Before any implementation:
- Present approach with **key code snippets** (20-30 lines per file)
- Reference `vision.md` and `conventions.md` sections
- Show: files to create/modify, methods, key decisions
- **Wait for approval** - Do not proceed without it

### **Step 2: IMPLEMENT**
After approval only:
- Create/modify files per approved plan
- Follow `conventions.md` strictly
- Implement **only** what was agreed
- No extras, no "improvements"

### **Step 3: TEST**
- Run test case from `tasklist.md` for this iteration
- Verify compilation (use `mcp1_analyze_files`)
- Run required commands (use MCP tools)
- Report results clearly

### **Step 4: UPDATE Progress**
In `tasklist.md`:
- Check all completed tasks [x]
- Update progress table (⏳ → 🚧 → ✅)
- Mark iteration header with "✅ COMPLETE"
- Update deliverable status

### **Step 5: CONFIRM & Next**
- Report completion with test results
- **Wait for approval** to proceed
- Move to next iteration only when approved
- Start next iteration from Step 1

---

## Task Completion Checklist

Each iteration is complete when:
- [ ] All checkboxes checked in `tasklist.md`
- [ ] Code compiles without errors
- [ ] Test case passes (specified in iteration)
- [ ] No regression in previous features
- [ ] Conventions followed (`conventions.md`)
- [ ] Progress table updated

---

## 💬 Communication Protocol

### Before Implementation
```
"Proposing Iteration N: [Feature Name]"

Approach:
- [Implementation strategy]
- References: vision.md §X, conventions.md §Y

Files to create/modify:
- `path/to/file.dart` - [purpose]

Key code snippets:
[Show 20-30 lines per file]

Ready to implement?
```

### After Implementation
```
"Completed Iteration N: [Feature Name]"

Files created/modified:
- [List files]

Test results:
- [Test case from tasklist.md]
- Status: ✅ Pass / ❌ Fail

Ready to proceed to Iteration N+1?
```

### If Blocked
```
"Blocked on Iteration N: [Issue]"

Problem: [Clear description]
Error: [Error message/behavior]
Proposed fix: [Solution]

Awaiting guidance.
```

---

## File Management Rules

### Do Create
- Only files specified in current iteration
- Required by approved solution
- Mentioned in `tasklist.md` for current step

### Don't Create
- Helper files not in plan
- Premature abstractions
- Extra utilities "for future use"
- Test files (unless iteration requires them)

---

## Code Changes Rules

### Always
- Follow existing code style exactly
- Use conventions from `conventions.md`
- Match indentation and formatting
- Add logging where specified
- Include error handling

### Never
- Skip agreed-upon steps
- Add features from future iterations
- Refactor working code without approval
- Change file structure without approval
- Remove existing functionality

---

## 🛠️ MCP Tools Usage

**IMPORTANT:** Use MCP tools, not shell commands

### Common Operations
```dart
// After adding dependencies
mcp1_pub(command: "get", roots: [{root: "file:///..."}])

// After modifying Freezed models  
// Run build_runner via terminal (MCP doesn't support this)
run_command: "flutter pub run build_runner build --delete-conflicting-outputs"

// Code analysis
mcp1_analyze_files()

// Formatting (per conventions.md)
run_command: "dart format . --line-length 120"
```

---

## Error Handling

### Compilation Error
1. Show full error message
2. Identify cause
3. Propose fix
4. Wait for approval

### Runtime Error
1. Show error and stack trace
2. Describe reproduction steps
3. Propose fix
4. Wait for approval

### Unexpected Behavior
1. Describe expected vs actual
2. Show relevant code
3. Propose diagnosis approach
4. Wait for guidance

---

## Testing Protocol

### Each Iteration
- Follow test case in `tasklist.md`
- Report test results clearly
- If test fails, treat as blocked
- Don't proceed until test passes

### Manual Testing Format
```
Test: [Description from tasklist]
Steps:
1. [Action]
2. [Action]
Expected: [Behavior]
Actual: [Behavior]
Status: ✅ Pass / ❌ Fail
```

---

## Status Icons Reference

- ⏳ **Pending** - Not started
- 🚧 **In Progress** - Currently working on
- ✅ **Complete** - Done and tested
- ❌ **Blocked** - Cannot proceed
- ⚠️ **Needs Review** - Requires attention

---

## 📚 Quick Reference

### 📍 Progress Tracking
**Source of Truth:** `tasklist.md` - Lines 3-20 (Progress table)

### 📖 Documentation
- **Architecture & Design:** `vision.md`
- **Code Standards:** `conventions.md`
- **Formatting Rules:** `code-style-guide.md`
- **Best Practices:** `guidelines.md`

### 📦 Key Dependencies
- `locker` (local) - MFALocker, BioCipherFunc, PasswordCipherFunc
- `secure_mnemonic` (local) - Biometric key generation
- `flutter_bloc` + `action_bloc` - State management
- `freezed` - Immutable models

---

## 📝 Example Interaction

**Assistant:**
```
Proposing Iteration 8: Biometric Constants & Dependencies

Approach:
- Add biometric constants to app_constants.dart
- Reference: vision.md §2.1 (BioCipherFunc setup)

Files to modify:
- `lib/core/constants/app_constants.dart`

Key additions:
static const biometricKeyTag = 'mfa_demo_bio_key';
static const biometricPromptTitle = 'Authenticate';
static const biometricPromptSubtitle = 'Use biometric to unlock';

Ready to implement?
```

**User:** "Approved"

**Assistant:** [Implements]
```
Completed Iteration 8: Biometric Constants & Dependencies

Files modified:
- lib/core/constants/app_constants.dart

Test: Constants accessible, no compilation errors
Status: ✅ Pass

Ready to proceed to Iteration 9?
```

**User:** "Proceed"

**Assistant:** "Proposing Iteration 9: Repository Layer - Biometric Methods..."

---

## ⚠️ Anti-Patterns (DON'T DO THIS)

❌ Implement without proposal  
❌ Skip approval/confirmation steps  
❌ Add features from future iterations  
❌ Modify files not in current iteration  
❌ Skip progress updates in tasklist.md  
❌ Proceed when tests fail  
❌ Ignore conventions.md rules  

---

## ✅ The Right Way

**PROPOSE** (with code) → **GET APPROVAL** → **IMPLEMENT** → **TEST** → **UPDATE** tasklist.md → **GET CONFIRMATION** → **NEXT**

---

## 📌 Summary

**One iteration at a time.**  
**Always propose first.**  
**Always wait for approval.**  
**Always update tasklist.md.**  
**Always get confirmation before next.**

**Current:** Phase 1 Complete ✅ | **Next:** Iteration 8 🚀
