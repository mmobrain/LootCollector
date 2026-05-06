import re
import os
import sys

def remove_lua_comments(content):
    """
    Remove all comments from Lua code while preserving string literals.
    Handles:
    - Single-line comments (-- comment)
    - Multi-line comments (--[[ comment ]])
    - Comments after code on the same line
    - String literals that might contain --
    """
    result = []
    i = 0
    length = len(content)
    
    while i < length:
        # Check for string literals first (single quotes)
        if content[i] == "'":
            end = i + 1
            while end < length:
                if content[end] == '\\':
                    end += 2
                    continue
                if content[end] == "'":
                    result.append(content[i:end+1])
                    i = end + 1
                    break
                end += 1
            else:
                result.append(content[i])
                i += 1
            continue
        
        # Check for string literals (double quotes)
        if content[i] == '"':
            end = i + 1
            while end < length:
                if content[end] == '\\':
                    end += 2
                    continue
                if content[end] == '"':
                    result.append(content[i:end+1])
                    i = end + 1
                    break
                end += 1
            else:
                result.append(content[i])
                i += 1
            continue
        
        # Check for multi-line string literals [[...]]
        if i < length - 1 and content[i:i+2] == '[[':
            end = content.find(']]', i + 2)
            if end != -1:
                result.append(content[i:end+2])
                i = end + 2
                continue
        
        # Check for multi-line comments --[[...]]
        if i < length - 3 and content[i:i+4] == '--[[':
            end = content.find(']]', i + 4)
            if end != -1:
                # Replace comment with single space to preserve line structure
                i = end + 2
                continue
            else:
                # Unclosed multi-line comment, skip rest of file
                break
        
        # Check for single-line comments --
        if i < length - 1 and content[i:i+2] == '--':
            # Find end of line
            end = content.find('\n', i)
            if end != -1:
                result.append('\n')  # Keep the newline
                i = end + 1
            else:
                # Comment goes to end of file
                break
            continue
        
        # Regular character
        result.append(content[i])
        i += 1
    
    return ''.join(result)

def process_file(filepath, output_path=None):
    """
    Process a single Lua file to remove comments.
    
    Args:
        filepath: Path to input .lua file
        output_path: Optional output path. If None, overwrites original file.
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        cleaned_content = remove_lua_comments(content)
        
        # Remove excessive blank lines (more than 2 consecutive)
        cleaned_content = re.sub(r'\n{3,}', '\n\n', cleaned_content)
        
        output_file = output_path or filepath
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(cleaned_content)
        
        print(f"Processed: {filepath}")
        if output_path:
            print(f"  Output: {output_path}")
        
        return True
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

def process_directory(directory, recursive=False, backup=True):
    """
    Process all .lua files in a directory.
    
    Args:
        directory: Directory path to process
        recursive: Process subdirectories recursively
        backup: Create .bak backup files before processing
    """
    lua_files = []
    
    if recursive:
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.endswith('.lua'):
                    lua_files.append(os.path.join(root, file))
    else:
        lua_files = [os.path.join(directory, f) for f in os.listdir(directory) 
                     if f.endswith('.lua') and os.path.isfile(os.path.join(directory, f))]
    
    print(f"Found {len(lua_files)} .lua file(s)")
    
    for filepath in lua_files:
        if backup:
            backup_path = filepath + '.bak'
            try:
                with open(filepath, 'r', encoding='utf-8') as src:
                    with open(backup_path, 'w', encoding='utf-8') as dst:
                        dst.write(src.read())
            except Exception as e:
                print(f"Failed to create backup for {filepath}: {e}")
                continue
        
        process_file(filepath)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  Single file: python remove_comments.py <file.lua> [output.lua]")
        print("  Directory:   python remove_comments.py <directory> [--recursive] [--no-backup]")
        sys.exit(1)
    
    path = sys.argv[1]
    
    if os.path.isfile(path):
        # Single file mode
        output_path = sys.argv[2] if len(sys.argv) > 2 else None
        process_file(path, output_path)
    elif os.path.isdir(path):
        # Directory mode
        recursive = '--recursive' in sys.argv or '-r' in sys.argv
        backup = '--no-backup' not in sys.argv
        process_directory(path, recursive, backup)
    else:
        print(f"Error: {path} is not a valid file or directory")
        sys.exit(1)
