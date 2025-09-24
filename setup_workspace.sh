#!/bin/bash

# Script to help setup the workspace configuration
# Run this script and then open Xcode to complete the manual steps

cd /Users/justingardner/Downloads/xcode/books_tracker_v1

echo "Current workspace structure:"
echo "- BooksTracker.xcworkspace"
echo "- BooksTracker.xcodeproj (app shell)"
echo "- BooksTrackerPackage/ (Swift Package)"
echo ""

echo "Next steps:"
echo "1. Open BooksTracker.xcworkspace in Xcode"
echo "2. Add BooksTrackerPackage as a local package dependency"
echo "3. Link BooksTrackerFeature to the BooksTracker app target"
echo ""

echo "Opening workspace in Xcode..."
open BooksTracker.xcworkspace