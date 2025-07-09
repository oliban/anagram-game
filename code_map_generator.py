#!/usr/bin/env python3

import argparse
import os
import re
from typing import List, Dict, Optional, Tuple

class SwiftCodeMapGenerator:
    def __init__(self):
        self.api_surface = []
        
    def extract_imports(self, content: str) -> List[str]:
        """Extract import statements"""
        import_pattern = r'^import\s+.*$'
        return re.findall(import_pattern, content, re.MULTILINE)
    
    def extract_protocols(self, content: str) -> List[str]:
        """Extract protocol declarations with inheritance and method signatures"""
        protocols = []
        lines = content.split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i].strip()
            
            # Match protocol declarations with inheritance
            protocol_match = re.match(r'^(\s*)((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+)?protocol\s+(\w+)(\s*:\s*[^{]+)?\s*\{', line)
            
            if protocol_match:
                indent = protocol_match.group(1)
                annotations = protocol_match.group(2).strip()
                access_modifier = protocol_match.group(3) or ""
                protocol_name = protocol_match.group(4)
                inheritance = protocol_match.group(5) or ""
                
                protocol_lines = []
                if annotations:
                    protocol_lines.append(f"{annotations}")
                protocol_lines.append(f"{access_modifier}protocol {protocol_name}{inheritance} {{")
                
                # Extract protocol methods and properties
                brace_count = 1
                j = i + 1
                
                while j < len(lines) and brace_count > 0:
                    current_line = lines[j]
                    stripped = current_line.strip()
                    
                    brace_count += stripped.count('{') - stripped.count('}')
                    
                    if brace_count == 1 and stripped and not stripped.startswith('//'):
                        # Extract method signatures
                        func_match = re.match(r'\s*((?:@\w+(?:\([^)]*\))?\s+)*)(static\s+|class\s+)?func\s+([^{]+)', stripped)
                        if func_match:
                            method_annotations = func_match.group(1).strip()
                            static_modifier = func_match.group(2) or ""
                            method_signature = func_match.group(3).strip()
                            
                            if method_annotations:
                                protocol_lines.append(f"    {method_annotations}")
                            protocol_lines.append(f"    {static_modifier}func {method_signature}")
                        
                        # Extract property requirements
                        var_match = re.match(r'\s*(var|let)\s+(\w+)\s*:\s*([^{]+)', stripped)
                        if var_match:
                            var_type = var_match.group(1)
                            var_name = var_match.group(2)
                            var_decl = var_match.group(3).strip()
                            protocol_lines.append(f"    {var_type} {var_name}: {var_decl}")
                    
                    j += 1
                
                protocol_lines.append("}")
                protocols.append('\n'.join(protocol_lines))
                i = j
            else:
                i += 1
                
        return protocols
    
    def extract_types(self, content: str) -> List[str]:
        """Extract class/struct/enum declarations with full API surface"""
        types = []
        lines = content.split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i].strip()
            
            # Match type declarations with annotations and inheritance
            type_match = re.match(r'^(\s*)((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(final\s+)?(class|struct|enum)\s+(\w+)(<[^>]+>)?(\s*:\s*[^{]+)?\s*\{', line)
            
            if type_match:
                indent = type_match.group(1)
                annotations = type_match.group(2).strip()
                access_modifier = type_match.group(3) or ""
                final_modifier = type_match.group(4) or ""
                type_keyword = type_match.group(5)
                type_name = type_match.group(6)
                generics = type_match.group(7) or ""
                inheritance = type_match.group(8) or ""
                
                type_lines = []
                
                # Add annotations
                if annotations:
                    for annotation in annotations.split('\n'):
                        if annotation.strip():
                            type_lines.append(annotation.strip())
                
                # Add type declaration
                type_decl = f"{access_modifier}{final_modifier}{type_keyword} {type_name}{generics}{inheritance} {{"
                type_lines.append(type_decl)
                
                # Extract type contents
                brace_count = 1
                j = i + 1
                
                while j < len(lines) and brace_count > 0:
                    current_line = lines[j]
                    stripped = current_line.strip()
                    
                    brace_count += stripped.count('{') - stripped.count('}')
                    
                    if brace_count == 1 and stripped and not stripped.startswith('//'):
                        # Extract properties
                        prop_match = re.match(r'\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(static\s+|class\s+)?(weak\s+|unowned\s+)?(var|let)\s+(\w+)\s*:\s*([^={\n]+)', stripped)
                        if prop_match:
                            prop_annotations = prop_match.group(1).strip()
                            prop_access = prop_match.group(2) or ""
                            prop_static = prop_match.group(3) or ""
                            prop_weak = prop_match.group(4) or ""
                            prop_kind = prop_match.group(5)
                            prop_name = prop_match.group(6)
                            prop_type = prop_match.group(7).strip()
                            
                            # Only include public/internal properties (exclude private)
                            if not prop_access.strip().startswith('private') and not prop_access.strip().startswith('fileprivate'):
                                if prop_annotations:
                                    for annotation in prop_annotations.split('\n'):
                                        if annotation.strip():
                                            type_lines.append(f"    {annotation.strip()}")
                                
                                prop_line = f"    {prop_access}{prop_static}{prop_weak}{prop_kind} {prop_name}: {prop_type}"
                                type_lines.append(prop_line)
                        
                        # Extract computed properties with getters/setters
                        computed_match = re.match(r'\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(static\s+|class\s+)?(var)\s+(\w+)\s*:\s*([^{]+)\s*\{', stripped)
                        if computed_match:
                            comp_annotations = computed_match.group(1).strip()
                            comp_access = computed_match.group(2) or ""
                            comp_static = computed_match.group(3) or ""
                            comp_name = computed_match.group(5)
                            comp_type = computed_match.group(6).strip()
                            
                            if not comp_access.strip().startswith('private') and not comp_access.strip().startswith('fileprivate'):
                                if comp_annotations:
                                    for annotation in comp_annotations.split('\n'):
                                        if annotation.strip():
                                            type_lines.append(f"    {annotation.strip()}")
                                
                                comp_line = f"    {comp_access}{comp_static}var {comp_name}: {comp_type} {{ get }}"
                                type_lines.append(comp_line)
                        
                        # Extract methods with full signatures
                        func_match = re.match(r'\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(static\s+|class\s+|override\s+)*(func|init|deinit)\s+([^{]+)', stripped)
                        if func_match:
                            func_annotations = func_match.group(1).strip()
                            func_access = func_match.group(2) or ""
                            func_modifiers = func_match.group(3) or ""
                            func_keyword = func_match.group(4)
                            func_signature = func_match.group(5).strip()
                            
                            # Only include public/internal methods
                            if not func_access.strip().startswith('private') and not func_access.strip().startswith('fileprivate'):
                                if func_annotations:
                                    for annotation in func_annotations.split('\n'):
                                        if annotation.strip():
                                            type_lines.append(f"    {annotation.strip()}")
                                
                                func_line = f"    {func_access}{func_modifiers}{func_keyword} {func_signature}"
                                type_lines.append(func_line)
                    
                    j += 1
                
                type_lines.append("}")
                types.append('\n'.join(type_lines))
                i = j
            else:
                i += 1
                
        return types
    
    def extract_global_functions(self, content: str) -> List[str]:
        """Extract global function declarations with full signatures"""
        functions = []
        lines = content.split('\n')
        inside_type = False
        brace_count = 0
        
        for line in lines:
            stripped = line.strip()
            
            # Track if we're inside a type declaration
            if re.match(r'^\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(final\s+)?(class|struct|enum|protocol)\s+\w+', stripped):
                inside_type = True
                brace_count = 0
            
            if inside_type:
                brace_count += stripped.count('{') - stripped.count('}')
                if brace_count <= 0:
                    inside_type = False
            
            # Extract global functions
            if not inside_type:
                func_match = re.match(r'^\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(static\s+)?func\s+([^{]+)', stripped)
                if func_match and not stripped.startswith('//'):
                    func_annotations = func_match.group(1).strip()
                    access_modifier = func_match.group(2) or ""
                    static_modifier = func_match.group(3) or ""
                    func_signature = func_match.group(4).strip()
                    
                    # Only include public/internal functions
                    if not access_modifier.strip().startswith('private') and not access_modifier.strip().startswith('fileprivate'):
                        if func_annotations:
                            functions.append(func_annotations)
                        functions.append(f"{access_modifier}{static_modifier}func {func_signature}")
        
        return functions
    
    def extract_extensions(self, content: str) -> List[str]:
        """Extract extension declarations with their public API"""
        extensions = []
        lines = content.split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i].strip()
            
            extension_match = re.match(r'^(\s*)((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+)?extension\s+(\w+)(\s*:\s*[^{]+)?\s*\{', line)
            
            if extension_match:
                indent = extension_match.group(1)
                annotations = extension_match.group(2).strip()
                access_modifier = extension_match.group(3) or ""
                type_name = extension_match.group(4)
                conformance = extension_match.group(5) or ""
                
                extension_lines = []
                if annotations:
                    extension_lines.append(annotations)
                extension_lines.append(f"{access_modifier}extension {type_name}{conformance} {{")
                
                # Extract extension contents
                brace_count = 1
                j = i + 1
                
                while j < len(lines) and brace_count > 0:
                    current_line = lines[j]
                    stripped = current_line.strip()
                    
                    brace_count += stripped.count('{') - stripped.count('}')
                    
                    if brace_count == 1 and stripped and not stripped.startswith('//'):
                        # Extract methods from extension
                        func_match = re.match(r'\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(static\s+|class\s+)?func\s+([^{]+)', stripped)
                        if func_match:
                            func_annotations = func_match.group(1).strip()
                            func_access = func_match.group(2) or ""
                            func_modifiers = func_match.group(3) or ""
                            func_signature = func_match.group(4).strip()
                            
                            if not func_access.strip().startswith('private') and not func_access.strip().startswith('fileprivate'):
                                if func_annotations:
                                    extension_lines.append(f"    {func_annotations}")
                                extension_lines.append(f"    {func_access}{func_modifiers}func {func_signature}")
                        
                        # Extract computed properties from extension
                        var_match = re.match(r'\s*((?:@\w+(?:\([^)]*\))?\s+)*)(public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(static\s+|class\s+)?var\s+(\w+)\s*:\s*([^{]+)\s*\{', stripped)
                        if var_match:
                            var_annotations = var_match.group(1).strip()
                            var_access = var_match.group(2) or ""
                            var_modifiers = var_match.group(3) or ""
                            var_name = var_match.group(4)
                            var_type = var_match.group(5).strip()
                            
                            if not var_access.strip().startswith('private') and not var_access.strip().startswith('fileprivate'):
                                if var_annotations:
                                    extension_lines.append(f"    {var_annotations}")
                                extension_lines.append(f"    {var_access}{var_modifiers}var {var_name}: {var_type} {{ get }}")
                    
                    j += 1
                
                extension_lines.append("}")
                extensions.append('\n'.join(extension_lines))
                i = j
            else:
                i += 1
                
        return extensions

def generate_code_map(file_path: str) -> str:
    """Generate a comprehensive Swift API surface map"""
    with open(file_path, 'r', encoding='utf-8') as f:
        source_code = f.read()
    
    generator = SwiftCodeMapGenerator()
    
    # Extract all API components
    imports = generator.extract_imports(source_code)
    protocols = generator.extract_protocols(source_code)
    types = generator.extract_types(source_code)
    global_functions = generator.extract_global_functions(source_code)
    extensions = generator.extract_extensions(source_code)
    
    # Build the complete API surface
    api_components = []
    
    # Add timestamp header
    from datetime import datetime
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    api_components.append(f"// Generated: {timestamp}")
    api_components.append("")
    
    # Add imports
    if imports:
        api_components.extend(imports)
        api_components.append("")
    
    # Add protocols
    if protocols:
        api_components.extend(protocols)
        api_components.append("")
    
    # Add types (classes, structs, enums)
    if types:
        api_components.extend(types)
        api_components.append("")
    
    # Add global functions
    if global_functions:
        api_components.extend(global_functions)
        api_components.append("")
    
    # Add extensions
    if extensions:
        api_components.extend(extensions)
    
    return '\n'.join(api_components)

def main():
    parser = argparse.ArgumentParser(
        description='Generate a Swift API surface code map that extracts public interfaces without implementation details.',
        usage='python3 code_map_generator.py <path> [path...] --output <file>'
    )
    parser.add_argument('paths', metavar='path', type=str, nargs='+',
                        help='Swift file or directory to process.')
    parser.add_argument('--output', type=str, help='Output file for the code map.')
    
    args = parser.parse_args()
    
    output_lines = []
    
    for path in args.paths:
        if os.path.isfile(path) and path.endswith('.swift'):
            from datetime import datetime
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            output_lines.append(f"// Generated: {timestamp}")
            output_lines.append(f"// Swift API Surface Map for: {path}")
            output_lines.append("// Generated by Swift Code Map Generator")
            output_lines.append("// Contains: imports, protocols, classes/structs/enums, global functions, extensions")
            output_lines.append("// Excludes: implementation details, private members")
            output_lines.append("")
            
            try:
                code_map = generate_code_map(path)
                if code_map.strip():
                    output_lines.append(code_map)
                else:
                    output_lines.append("// No public API surface found")
            except Exception as e:
                output_lines.append(f"// Error processing file: {str(e)}")
            
            output_lines.append("")
            output_lines.append("/" * 100)
            output_lines.append("")
            
        elif os.path.isdir(path):
            swift_files = []
            for root, _, files in os.walk(path):
                for file in files:
                    if file.endswith('.swift'):
                        swift_files.append(os.path.join(root, file))
            
            if swift_files:
                from datetime import datetime
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                output_lines.append(f"// Generated: {timestamp}")
                output_lines.append(f"// Swift API Surface Map for directory: {path}")
                output_lines.append(f"// Found {len(swift_files)} Swift files")
                output_lines.append("// Generated by Swift Code Map Generator")
                output_lines.append("")
                
                for file_path in sorted(swift_files):
                    output_lines.append(f"// === {file_path} ===")
                    output_lines.append("")
                    
                    try:
                        code_map = generate_code_map(file_path)
                        if code_map.strip():
                            output_lines.append(code_map)
                        else:
                            output_lines.append("// No public API surface found")
                    except Exception as e:
                        output_lines.append(f"// Error processing file: {str(e)}")
                    
                    output_lines.append("")
                    output_lines.append("/" * 100)
                    output_lines.append("")
    
    output_content = '\n'.join(output_lines)
    
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output_content)
        print(f"Swift API surface map written to: {args.output}")
        print(f"Generated {len(output_lines)} lines of API surface documentation")
    else:
        print(output_content)

if __name__ == "__main__":
    main()