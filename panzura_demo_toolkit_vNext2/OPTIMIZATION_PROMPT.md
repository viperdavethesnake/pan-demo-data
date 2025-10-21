# Background Agent Prompt: File Creation Performance Optimization

## Task Overview
Optimize PowerShell file creation scripts for maximum performance using parallel processing, threading, and advanced PowerShell techniques.

## Context
You have a Panzura demo toolkit with file creation scripts that generate enterprise-realistic file structures. The current scripts are sequential and slow. You need to dramatically speed up file creation using:

1. **PowerShell Runspaces** - For true parallel processing
2. **PowerShell Jobs** - For background processing  
3. **Batch Operations** - Grouping file operations
4. **Async AD Queries** - Parallel Active Directory lookups
5. **Optimized Sparse Files** - Bulk sparse file operations
6. **Memory Management** - Efficient resource usage

## Key Requirements
- Maintain all existing functionality (AD integration, realistic timestamps, file types, ownership)
- Support the same parameters and folder-aware distribution
- Keep the sophisticated normal distribution logic
- Preserve all enterprise realism features
- Add comprehensive progress reporting for parallel operations
- Handle errors gracefully in parallel scenarios
- Optimize for both small (1K files) and large (100K+ files) scenarios

## Performance Targets
- 10x speed improvement for large file counts
- Efficient memory usage (don't load everything into memory)
- Maintainable code structure
- Backward compatibility with existing scripts

## Technical Focus Areas
1. **Runspace Pools** - Create worker threads for file creation
2. **Parallel AD Queries** - Batch and cache AD lookups
3. **Bulk File Operations** - Group sparse file creation
4. **Smart Batching** - Process files in optimal batch sizes
5. **Resource Management** - Prevent memory leaks and handle cleanup
6. **Progress Aggregation** - Combine progress from multiple threads

## Deliverables Required

### 1. New Scripts (Output)
- Create optimized scripts in a new `vNext3` folder
- `create_files_parallel.ps1` - Main parallel file creation script
- `create_folders_parallel.ps1` - Parallel folder creation if needed
- `create_temp_pollution_parallel.ps1` - Parallel temp file generation
- Any supporting utility scripts for parallel operations

### 2. Summary Report
- Executive summary of performance improvements achieved
- Key optimization techniques implemented
- Performance benchmarks (before/after metrics)
- Resource usage improvements
- Compatibility assessment

### 3. Detailed Technical Report
- Comprehensive analysis of optimization strategies used
- Code architecture decisions and rationale
- Performance profiling results
- Memory usage analysis
- Error handling strategies
- Threading and concurrency patterns
- AD integration optimizations
- Sparse file operation improvements
- Progress reporting enhancements

## Success Criteria
- Achieve 5-10x performance improvement
- Maintain all existing functionality
- Handle edge cases and errors gracefully
- Provide clear performance metrics and logging
- Create production-ready parallel scripts

## Output Structure
```
panzura_demo_toolkit_vNext3/
├── create_files_parallel.ps1
├── create_folders_parallel.ps1
├── create_temp_pollution_parallel.ps1
├── parallel_utilities.psm1
├── PERFORMANCE_REPORT.md
└── OPTIMIZATION_SUMMARY.md
```

## Additional Notes
- Focus on PowerShell 5.1+ and PowerShell 7+ compatibility
- Ensure scripts work in both Windows and cross-platform scenarios
- Include comprehensive error handling and logging
- Provide clear documentation for new parallel features
- Maintain backward compatibility with existing parameter sets
