export function show_cheating(screen, task, submit, utils) {
    utils.make_basic_screen(screen, task);
    screen.classList.add("welcome_screen");
    utils.show_title(screen, task);
    utils.show_markdown_body(screen, task, task.taskbody.body);
    utils.make_next_button(screen, task, submit);
}


