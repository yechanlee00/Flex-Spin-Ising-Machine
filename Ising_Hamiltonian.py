from google.colab import drive
drive.mount('/content/drive')

import os
import numpy as np
import matplotlib.pyplot as plt

# FlexSpin txt files directory
os.chdir('/content/drive/MyDrive/Colab Notebooks/FlexSpin')

print("Current directory:", os.getcwd())


hamiltonian_file_wo = "Ising_Hamiltonian_wo_annealing.txt"
hamiltonian_file_w = "Ising_Hamiltonian_w_annealing.txt"


def load_hamiltonian_file(filename):
    if not os.path.exists(filename):
        raise FileNotFoundError(f"File not found: {filename}")

    rows = []

    with open(filename, "r") as file:
        for line_number, line in enumerate(file, start=1):
            line = line.strip()

            # Ignore empty lines and comment lines
            if not line or line.startswith("#"):
                continue

            values = line.split()

            if len(values) < 4:
                raise ValueError(
                    f"{filename}, line {line_number}: "
                    "expected four columns"
                )

            step = int(values[0])
            hamiltonian = int(values[1])
            flip_count = int(values[2])
            anneal_weight = int(values[3])

            rows.append(
                [
                    step,
                    hamiltonian,
                    flip_count,
                    anneal_weight
                ]
            )

    data = np.array(rows, dtype=int)

    if data.shape[0] == 0:
        raise ValueError(
            f"{filename}: no valid numerical data found"
        )

    return data


data_wo = load_hamiltonian_file(
    hamiltonian_file_wo
)

data_w = load_hamiltonian_file(
    hamiltonian_file_w
)


step_wo = data_wo[:, 0]
hamiltonian_wo = data_wo[:, 1]

step_w = data_w[:, 0]
hamiltonian_w = data_w[:, 1]


plt.figure(figsize=(10, 6))

plt.plot(
    step_wo,
    hamiltonian_wo,
    label="Without Annealing",
    linewidth=2
)

plt.plot(
    step_w,
    hamiltonian_w,
    label="With Exponential Annealing",
    linewidth=2
)

plt.title(
    "FlexSpin: Ising Hamiltonian Comparison",
    fontsize=15
)

plt.xlabel(
    "Spin Update Step",
    fontsize=12
)

plt.ylabel(
    "Ising Hamiltonian",
    fontsize=12
)

plt.grid(
    True,
    alpha=0.3
)

plt.legend(
    fontsize=11
)

plt.tight_layout()
plt.show()


print("Final Hamiltonian without annealing:",
      hamiltonian_wo[-1])

print("Final Hamiltonian with annealing:",
      hamiltonian_w[-1])

print(
    "Difference (with - without):",
    hamiltonian_w[-1] - hamiltonian_wo[-1]
)
