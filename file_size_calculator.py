import math
import readline  # Enables proper backspace handling on Unix-like systems

def calculate_adjusted_file_size(total_volume_gib, num_files):
    """
    Calculate the file size in MiB for each file such that the total volume 
    (in GiB) is distributed among num_files. If the raw file size is >= 4 MiB,
    round it up to the nearest multiple of 4. If it's less than 4 MiB, round up 
    to the nearest integer.
    
    Parameters:
        total_volume_gib (float): Total data volume in GiB.
        num_files (int): Number of files.
    
    Returns:
        int: Adjusted file size in MiB.
    """
    total_volume_mib = total_volume_gib * 1024  # Convert GiB to MiB
    raw_size_mib = total_volume_mib / num_files
    
    if raw_size_mib >= 4:
        adjusted_size_mib = math.ceil(raw_size_mib / 4) * 4
    else:
        adjusted_size_mib = math.ceil(raw_size_mib)
    
    return adjusted_size_mib

def main():
    try:
        total_volume_gib = float(input("Enter the total data volume (GiB): "))
        file_counts_input = input("Enter the number(s) of files (comma separated if multiple): ")
        
        # Parse the comma-separated values into a list of integers.
        file_counts = [int(count.strip()) for count in file_counts_input.split(",")]
        
        for num_files in file_counts:
            if num_files <= 0:
                print(f"Invalid number of files: {num_files}. Must be greater than 0.")
                continue
            
            adjusted_size_mib = calculate_adjusted_file_size(total_volume_gib, num_files)
            adjusted_size_gib = adjusted_size_mib / 1024  # Convert MiB to GiB
            adjusted_size_kib = adjusted_size_mib * 1024   # Convert MiB to KiB
            
            print(f"\nFor {num_files} file(s):")
            print(f"  {adjusted_size_gib:.3f} GiB per file")
            print(f"  {adjusted_size_mib} MiB per file")
            print(f"  {adjusted_size_kib} KiB per file")
        
    except ValueError:
        print("Invalid input. Please enter numeric values.")

if __name__ == "__main__":
    main()