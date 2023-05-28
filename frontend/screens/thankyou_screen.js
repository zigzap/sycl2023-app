export function show_thankyou(screen, task, submit, utils) {
    utils.make_basic_screen(screen, task);
    screen.classList.add("thankyou_screen");
    utils.show_title(screen, task);
    utils.show_markdown_body(screen, task, task.taskbody.body);
    utils.make_next_button(screen, task);
    submit({"finished": true});
    if(task.final_task === true) {
        console.log("removing onbeforeunload");
        window.onbeforeunload = null;
    }
}

