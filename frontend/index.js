import { show_welcome } from "./screens/welcome_screen.js?version=0";
import { show_thankyou } from "./screens/thankyou_screen.js?version=0";
import { show_qscreen } from "./screens/qscreen.js?version=0";
import { show_cheating } from "./screens/cheatscreen.js?version=0";
import { loadInitialTask, loadUserTask, reloadTaskTemplate } from "./api.js?version=0";
import { setCookie, getCookie } from "./cookies.js?version=0";

var eScreen = document.getElementById("screen");

var state = {
    userid : "null",
    current_task_id : 0,
    task : null,
    iter : 0,
};

var utils = {
    isoTimeStamp : function() {
        return new Date().toISOString().replace("T", " ").replace("Z", "");
    },

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
        document.getElementById("loader").style.display = "none";
        document.getElementById("screen").style.display = "block";
        window.scrollTo(0,0);
        screen.classList.remove("welcome_screen");
        screen.classList.remove("q_screen");
        screen.classList.remove("thankyou_screen");
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
        // setting ID does not seem to work
        // so we will have to access the button later via class

        if(!submit_fn) {
            b.onclick = function() {
                // we didn't get a submit function passed in
                // so we need to call our final submit function directly
                // however, it accepts an appdata object. we have no
                // choice but to send an empty one.
                // Note, that in this codebase, the function call below
                // is never executed. It's an error, if it is. Exactly
                // because of the appdata sending business.
                // So, the way it works, is: The passed in submit_fn
                // points to the pre_submit() function of the screen.
                // Here, validation checks are done, e.g. are all Qs
                // answered, etc. Only if it's OK to really submit, the
                // real submit function, that was passed in to the
                // screen, is called from within the individual pre_submit
                // function of the screen.
                submit({});
            }
        } else {
            b.onclick = function() {
                // usually calls back into the screen's pre_submit()
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

function cheatSubmit() {
    loadInitialTask(on_task_loaded);
}

async function init() {
    state.current_task_id = 0;
    state.userid = "null";

    // disable back button
    window.onbeforeunload = function() { return "Your work will be lost."; };
    history.pushState(null, document.title, location.href);
    window.addEventListener('popstate', function (event)
    {
      history.pushState(null, document.title, location.href);
    });

    // TODO: while developing:
    //
    // DANGER: make sure to disable this reloading in production or else
    // every new user will trigger reloading. 
    //
    // THIS CAN LEAD TO RACE CONDITIONS with potential crashes as the
    // result: the task json template is not mutex protected so we don't
    // content on it for every single task render. If the json template
    // is freed mid-rendering, this is bound to cause a crash!
    //
    // maybe, indicate this visually somehow - maybe with the
    // snackbar?
    reloadTaskTemplate();
    utils.showToast("Task template reloaded. Disable this before going into production!");

    let cookie = getCookie("SYCL2023");

    if(cookie != "" && cookie != "true") {
        eScreen.innerHTML = ' ';
        let task = {
            tasktype: "cheating",
            taskbody : {
                heading: "Are you sure?",
                body: "Participating more than once is considered `cheating` and will distort the collected survey data.",
            },
            next_button: "Yes, I want to cheat!"
        };
        show_cheating(eScreen, task, cheatSubmit, utils); 
    } else {
        loadInitialTask(on_task_loaded);
    }
}


init();

function submit(appdata) {
    // post update to server and get next task
    setCookie("SYCL2023", "agreed", 3);
    let next = state.task.next_task;
    let final = state.task.final;
    console.log("final is", final);

    if (final === true || next === null || next === undefined) return;

    state.current_task_id = next;

    // make the button disappear immediately so we can't press it twice
    // if we're fancy, we could display a loading animation here. this
    // is necessary if load times increase when the server is under high
    // load, our connection is crappy, etc.
    //
    // we'll do the disappearing business in load_next_task().
    load_next_task(appdata);
}

function on_task_loaded(response) {
    console.log("New task response", response);
    if (Array.isArray(response)) {
        state.userid = response[0];
        console.log("we got a user id", state.userid);
        state.task = response[1];
    } else {
        state.task = response;
    }
    if(state.task === null) {
        console.log("TASK IS NULL");
        return;
    }

    // if we ever need to update src/data/dummy_data.json:
    // console.log(JSON.stringify(dummy_tasks));
    console.log("RUNNING IT");
    run();
}

function load_next_task(appdata) {
    console.log("Taskid is now", state.current_task_id);
    // make the button disappear immediately so we can't press it twice
    // if we're fancy, we could display a loading animation here. this
    // is necessary if load times increase when the server is under high
    // load, our connection is crappy, etc.

    // TODO: does not work, is null
    let buttons = document.getElementsByClassName("nextbutton");
    for(let button of buttons) {
        console.log("button is" , button);
        button.style.display = "none";
    }
    document.getElementById("screen").style.display = "none";
    document.getElementById("loader").style.display = "block";
    loadUserTask(state.userid, state.current_task_id, appdata, on_task_loaded);
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


