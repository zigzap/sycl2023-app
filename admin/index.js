var eScreen = document.getElementById("screen");

var state = {
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

async function on_save() {
    const response = await fetch("/admin/save");
    const data = await response.json();
    utils.showToast(JSON.stringify(data));
}



async function init() {
    state.current_task_id = 0;
    state.userid = "null";

    var x = document.getElementById("SAVE");
    x.innerHTML = '<a id="X" style="color:4ccaf4" href="#" >SAVE DATA TO TAPE</a>'
    var X = document.getElementById("X");
    X.onclick = on_save;
    // disable back button
    // window.onbeforeunload = function() { return "Your inputs will be lost."; };
    // history.pushState(null, document.title, location.href);
    // window.addEventListener('popstate', function (event)
    // {
    //   history.pushState(null, document.title, location.href);
    // });
}


init();


