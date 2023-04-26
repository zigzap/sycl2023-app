import { show_welcome } from "./screens/welcome_screen.js?version=0";
import { show_thankyou } from "./screens/thankyou_screen.js?version=0";
import { show_qscreen } from "./screens/qscreen.js?version=0";
import {loadUserTask, reloadTaskTemplate} from "./api.js?version=0";

var eScreen = document.getElementById("screen");

var state = {
    current_task_id : 0,
    task : null,
    iter : 0,
};

var utils = {
    shuffleArray : function(array) {
      if(array.length == 1)
        return;
      for (let i = array.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        const temp = array[i];
        array[i] = array[j];
        array[j] = temp;
      }
    },

    showToast : function(msg) {
        let snackbar = document.getElementById("snackbar");
        snackbar.innerHTML = msg;
        snackbar.className = "show";
        setTimeout(function(){ 
            snackbar.className = snackbar.className.replace("show", ""); 
        }, 3000);
    },

    make_basic_screen: function(screen, task) {
        console.log("utils.make_basic_screen:", task.tasktype);
        window.scrollTo(0,0);
    },

    make_next_button: function (screen, task, submit_fn) {
        if (task.next_button_hide) return;
        let d = null;
        let b = null;
        d = document.createElement("DIV");
        d.classList.add("next_div");

        b = document.createElement("BUTTON");
        b.innerHTML = task.next_button;
        b.classList.add("nextbutton");
        if(!submit_fn) {
            b.onclick = function() {
                submit();
            }
        } else {
            b.onclick = function() {
                submit_fn();
            }
        }

        d.appendChild(b);
        screen.appendChild(d);
    },

    show_title : function (screen, task) {
        if(!task.taskbody) return;
        if(!task.taskbody.heading) return;
        let converter = new showdown.Converter();
        let h = document.createElement("H1");
        h.innerHTML = converter.makeHtml(task.taskbody.heading);
        h.classList.add("title");
        screen.appendChild(h);
    },

    show_markdown_body: function(screen, task, body) {
        let converter = new showdown.Converter();
        let m = document.createElement("DIV");
        m.innerHTML = converter.makeHtml(body);
        m.classList.add("message");
        screen.appendChild(m);
    },
};

async function init() {
    state.current_task_id = 0;
    reloadTaskTemplate();
    load_next_task();
    // state.task = load_next_task();
    // if(state.task == null) return;
    //
    // // if we ever need to update src/data/dummy_data.json:
    // // console.log(JSON.stringify(dummy_tasks));
    // run();
}

init();

function submit() {
    // post update to server and get next task
    let next = state.task.next_task;
    let final = state.task.final;
    console.log("final is", final);

    if (final === true || next === null || next === undefined) return;

    state.current_task_id = next;
    load_next_task();
    // state.task = load_next_task()
    // if(state.task == null) return;
    // run();
}

function load_next_task() {
    console.log("Taskid is now", state.current_task_id);
    loadUserTask(1, state.current_task_id, on_task_loaded);
}

function on_task_loaded(task) {
    console.log("New task", task);
    state.task = task;
    if(state.task == null) return;

    // if we ever need to update src/data/dummy_data.json:
    // console.log(JSON.stringify(dummy_tasks));
    run();
}


function run() {
    state.iter += 1;
    // safety-net
    if(state.iter > 100) return;

    if(state.task) {
        // clear the div
        eScreen.innerHTML = ' ';
        let ttype = state.task.tasktype;
        console.log("type is", ttype);
        switch(ttype) {
            case "welcome" : show_welcome(eScreen, state.task, submit, utils); 
                break;
            case "thankyou" : show_thankyou(eScreen, state.task, submit, utils); 
                break;
            case "Q" : show_qscreen(eScreen, state.task, submit, utils);
                break;
            default:
                console.log("unknown task type", ttype);
                break;
        }
    }
}


