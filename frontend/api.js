// GETs the initial task for any user
export function loadInitialTask(callback) {
    const userid = null;
    const taskid = 0;
    const url = `/sycl-api/tasks/${taskid}?userid=${userid}`;
    fetch(url)
    .then(data=>{return data.json()})
    .then(res=>{callback(res);});
}

export function loadUserTask(userid, taskid, appdata_update, callback) {
    console.log("loadUserTask params:", userid, taskid, appdata_update, callback);
    const url = `/sycl-api/tasks/${taskid}?userid=${userid}`;
    fetch(url,
        {
            method: 'POST',
            headers: {
                "Accept": "application/json",
                "Content-Type": "application/json"
            },
            body: JSON.stringify(appdata_update)
        }
    )
    .then(data=>{return data.json()})
    .then(res=>{console.log(res); callback(res);});
}

export function reloadTaskTemplate() {
    const url = "/sycl-api/tasks/reload";
    fetch(url).then(_ => {})
}
