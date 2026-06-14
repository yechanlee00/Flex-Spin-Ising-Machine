from google.colab import drive
drive.mount('/content/drive')

import os
import numpy as np
import matplotlib.pyplot as plt

# FlexSpin txt files directory
os.chdir('/content/drive/MyDrive/Colab Notebooks/FlexSpin')

print("Current directory:", os.getcwd())


# Without annealing
files_wo_annealing = [
    "initial_spin.txt",
    "step1_result_wo_annealing.txt",
    "step10_result_wo_annealing.txt",
    "step20_result_wo_annealing.txt",
    "step30_result_wo_annealing.txt",
    "step60_result_wo_annealing.txt",
    "step90_result_wo_annealing.txt",
    "step120_result_wo_annealing.txt",
]

# With exponential annealing
files_w_annealing = [
    "initial_spin.txt",
    "step1_result.txt",
    "step10_result.txt",
    "step20_result.txt",
    "step30_result.txt",
    "step60_result.txt",
    "step90_result.txt",
    "step120_result.txt",
]

titles = [
    "Initial",
    "Step 1",
    "Step 10",
    "Step 20",
    "Step 30",
    "Step 60",
    "Step 90",
    "Step 120",
]


def load_spin_map(filename):
    if not os.path.exists(filename):
        raise FileNotFoundError(f"File not found: {filename}")

    with open(filename, "r") as file:
        lines = [
            line.strip()
            for line in file
            if line.strip()
        ]

    spin_map = np.array(
        [[int(bit) for bit in line] for line in lines],
        dtype=int
    )

    if spin_map.shape != (32, 32):
        raise ValueError(
            f"{filename}: shape is {spin_map.shape}, "
            "expected (32, 32)"
        )

    if not np.all(np.isin(spin_map, [0, 1])):
        raise ValueError(
            f"{filename}: the file must contain only 0 and 1"
        )

    return spin_map


maps_wo_annealing = [
    load_spin_map(filename)
    for filename in files_wo_annealing
]

maps_w_annealing = [
    load_spin_map(filename)
    for filename in files_w_annealing
]


# Top row: without annealing
# Bottom row: with exponential annealing
fig, axes = plt.subplots(
    2,
    8,
    figsize=(16, 5)
)

fig.suptitle(
    "FlexSpin: Ising Map Comparison",
    fontsize=16,
    y=0.98
)

for col, title in enumerate(titles):
    # Without annealing
    axes[0, col].imshow(
        maps_wo_annealing[col],
        cmap="gray",
        vmin=0,
        vmax=1,
        aspect="equal",
        origin="upper",
        interpolation="nearest"
    )

    axes[0, col].set_title(
        title,
        fontsize=10,
        pad=4
    )

    axes[0, col].set_xticks([])
    axes[0, col].set_yticks([])

    # With annealing
    axes[1, col].imshow(
        maps_w_annealing[col],
        cmap="gray",
        vmin=0,
        vmax=1,
        aspect="equal",
        origin="upper",
        interpolation="nearest"
    )

    axes[1, col].set_xticks([])
    axes[1, col].set_yticks([])


# Labels for the two experiment conditions
fig.text(
    0.01,
    0.68,
    "Without\nAnnealing",
    va="center",
    ha="left",
    fontsize=11
)

fig.text(
    0.01,
    0.27,
    "With\nAnnealing",
    va="center",
    ha="left",
    fontsize=11
)

plt.subplots_adjust(
    left=0.08,
    right=0.99,
    top=0.88,
    bottom=0.04,
    wspace=0.12,
    hspace=0.12
)

plt.show()
