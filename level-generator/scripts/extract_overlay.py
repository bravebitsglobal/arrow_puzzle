#!/usr/bin/env python3
"""
Extract obstacle overlay config from GDD Excel sheet 06
Output: overlay_config.json for Rust to load
"""

import sys
import json
import openpyxl
from pathlib import Path

def extract_overlay_config(excel_path: str, output_path: str):
    """Extract overlay config from sheet 06"""
    wb = openpyxl.load_workbook(excel_path, data_only=True)

    # Sheet 06: Obstacle Overlay 1-350
    ws = wb['06 Obstacle Overlay 1-350']

    configs = []

    # Start from row 5 (row 4 is header)
    # Columns: Level, Benchmark Base, Role, Forced Tutorial, Frozen Count, Frozen N list,
    #          Bomb Count, Bomb N list, Lock Groups, Locks/Group, Hidden Count, Hidden N list,
    #          Crate Count, Crate N list, Max Types
    for row in ws.iter_rows(min_row=5, max_row=354):  # 350 levels
        cells = [cell.value for cell in row]

        # Skip empty rows
        if not cells[0] or cells[0] == "Level":
            continue

        level = int(float(cells[0]))

        config = {
            "level": level,
            "benchmark_base": str(cells[1]) if cells[1] else "",
            "role": str(cells[2]) if cells[2] else "",
            "forced_tutorial": str(cells[3]) if cells[3] and cells[3] != "-" else None,
            "frozen": {
                "count": int(float(cells[4])) if cells[4] else 0,
                "n_list": parse_number_list(cells[5]) if cells[5] else []
            },
            "bomb": {
                "count": int(float(cells[6])) if cells[6] else 0,
                "n_list": parse_number_list(cells[7]) if cells[7] else []
            },
            "lock": {
                "groups": int(float(cells[8])) if cells[8] else 0,
                "locks_per_group": parse_number_list(cells[9]) if cells[9] else []
            },
            "hidden": {
                "count": int(float(cells[10])) if cells[10] else 0,
                "n_list": parse_number_list(cells[11]) if cells[11] else []
            },
            "crate": {
                "count": int(float(cells[12])) if cells[12] else 0,
                "n_list": parse_number_list(cells[13]) if cells[13] else []
            },
            "max_types": int(float(cells[14])) if cells[14] else 0
        }

        configs.append(config)

    # Write to JSON
    output = {"levels": configs}
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"Extracted {len(configs)} overlay configs to {output_path}")
    return len(configs)

def parse_number_list(cell_value):
    """Parse comma-separated numbers from Excel cell"""
    if not cell_value or cell_value == "-":
        return []

    s = str(cell_value)
    result = []
    for part in s.split(','):
        part = part.strip()
        if part and part != "-":
            try:
                result.append(int(float(part)))
            except ValueError:
                pass
    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_overlay.py <excel_path> [output_path]")
        sys.exit(1)

    excel_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "overlay_config.json"

    if not Path(excel_path).exists():
        print(f"Error: Excel file not found: {excel_path}")
        sys.exit(1)

    try:
        count = extract_overlay_config(excel_path, output_path)
        sys.exit(0 if count > 0 else 1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
