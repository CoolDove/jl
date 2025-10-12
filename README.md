# About "jl"
`jl` is a lightweight journaling tool inspired by 
[jrnl](https://jrnl.sh/en/stable/), but `jl` runs faster. `jl` is 
created with Jonathan Blow's language `jai`. Currently only runs on 
Windows.

# Requirements and configs
We don't have a config file now. Before using `jl`, make sure you have:
1. `JLEDITOR` or `EDITOR` in environment.
2. `JLDEFAULTFILE` in environment, specifying the file path. This is 
optional. By default the file will be in the user folder. You can see 
that path in first line of output of every command you run.

The `JLDEFAULTFILE` is a temporary solution, we will have a method to 
specify multiple jl files, maybe a config file.

# Records filtering
## By tags
- `jl @idea`

Search for records tagged with @idea in the title line.

- `jl @idea @jai`

Search for records tagged with both @idea **and** @jai in the title line.

## By date
- `jl 7d`

Match records from 7 days ago to today.

- `jl 2d:+6w`

Match records from 2 days ago to 6 weeks later.

- `jl -today|-t`

Match records on today.

- `jl -recent|-r`

Match records from 3 days ago to 3 days later.

# Operation
- create: `jl`

Create a new record, and edit with your editor.

- edit: `jl @jai --edit|--e`

Edit records tagged with @jl, with your own text editor. This is the 
default operation, `jl @jai` does the same thing. You can also delete 
records during editting.

- print: `jl @jai @syntax --print|--p`

Print matched records to the terminal.

- list tags: `jl @work --tags|--t`

List all tags in matched records.

- help: `jl --help|-help|--h|-h`

Print the help document.

# Encrypt
- `jl --encrypt`

To encrypt the jl file with a password. You will need to input the 
password when you want to modify a encrypted jl file.

- `jl --encrypt-save-key`

To encrypt, and save the key in your computer. You won't have to input 
the password everytime. Only do this when you're using your own computer.

- `jl --decrypt`

To decrypt the encrypted jl file. If you want to change the password, you 
can do this and encrypt again using your new password. If you got an 
encrypted jl file but the key is not stored, you can also decrypt it then 
--encrypt-save-key to reset the password and save the key.

- `jl --check`

Requires you to input the password and does nothing. I add this so that i 
can check if i'm still remembering the password. That makes me feel safe 
so i personally very need this.
