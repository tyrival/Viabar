# New Project Top Order Design

## Goal

Ensure each newly created project appears at the top of the active project list,
while projects restored from the archive continue to appear at the end.

## Root Cause

Active projects are displayed in ascending `orderIndex` order. New projects are
currently created with the default index `0` without shifting existing active
projects, leaving two or more projects with the same ordering value. Their visible
position is therefore not stable.

## Behavior

- Creating a project inserts it at active-list index `0`.
- Existing active projects retain their relative order and shift down by one.
- Restoring an archived project keeps the existing end-of-list behavior.
- Existing manual drag reordering continues to normalize active project order.

## Implementation

Implement insertion ordering in `ProjectService.createProject`. Before saving the
new project, fetch active projects in display order, clamp the requested insertion
index, and assign unique continuous order indices around that insertion. The
default creation call already requests index `0`, so `NewProjectView` requires no
sorting-specific change.

## Verification

Inspect the service data flow and run `git diff --check`. Do not compile or run
tests unless explicitly requested.
