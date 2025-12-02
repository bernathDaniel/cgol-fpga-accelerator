### How to run a Simulation with K5 Environment

## Step 1: Open 2 Terminals
At this step don't type "tsmc65" or anything, just open the terminal.

## Step 2: Type in each Terminal : "set_k5_terminal"
This is a shortcut that will open up "tsmc65" and direct us to the
workspace "sim" within the "CGOL" dir, this is where we run the simulation from.

## Step 3: Type in one of the Terminals : "launch_k5_app <folder_name>"
The cmd "launch_k5_app" is a shortcut to start the app and for each simulation
we need to have a different folder, the most basic examples are the folders :
"hello_k5" and "hello_me" - both can be used for checking out the system.

# Example (Launching hello_k5): Type "launch_k5_app hello_k5"

This will initiate the app, but nothing will happen and we'll see that it's waiting for
the other launch that's required in the 2nd terminal.

## Step 4: Type in the 2nd Terminal : "launch_k5_sim"

This will initiate the simulation itself aka the TB.
The TB isn't seen in this directory and it's referenced to a hidden location we have
no access to, so this shortcut is responsible for starting it.

# Note - Once we to steps 3 & 4 only then both terminals will start working and we'll see the results.
