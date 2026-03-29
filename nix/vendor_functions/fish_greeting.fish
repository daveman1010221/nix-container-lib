function fish_greeting --description="Displays a container welcome message."
    set_color $fish_color_autosuggestion
    set_color normal
    echo 'The license for this container can be found in /root/license.txt' | dotacat

    # Use CONTAINER_NAME from the environment if set, otherwise fall back
    # to the hostname (which is the container ID — less friendly but correct).
    set container_name (string trim -- "$CONTAINER_NAME")
    if test -z "$container_name"
        set container_name (hostname)
    end
    lol "Welcome to $container_name."

    # Array of coding phrases
    set phrases \
        "Next stop: Bug-free code!" \
        "Compiling dreams into reality." \
        "Borrow checker approved. Proceed." \
        "Your types are sound. Your logic is not. Good luck." \
        "Fearless concurrency awaits." \
        "No segfaults were harmed in the making of this shell." \
        "cargo build: the optimistic button." \
        "It compiles, therefore it is correct. Probably." \
        "Lifetime annotations: nature's way of saying slow down." \
        "Every unwrap() is a promise to yourself." \
        "Move semantics: because sharing is overrated." \
        "Making the impossible merely difficult since 2015." \
        "The borrow checker is not your enemy. It just plays one." \
        "Rewriting it in Rust was always the answer." \
        "Zero-cost abstractions, infinite-cost debugging." \
        "It's not a bug, it's an unscheduled feature." \
        "Undefined behavior? Not in this shell." \
        "async/await: because blocking is a character flaw." \
        "If it compiles and the tests pass, ship it." \
        "Today's segfault is tomorrow's memory safety lesson."

    # Select a random phrase
    set random_index (random 1 (count $phrases))
    echo $phrases[$random_index] | dotacat
end
