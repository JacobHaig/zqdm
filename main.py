from tqdm import tqdm
import time 

def main():
    slice = "Hello, World!"
    
    for val in tqdm(slice):
        time.sleep(0.1)
        print(val, end=' ')
    print()

if __name__ == "__main__":
    main()