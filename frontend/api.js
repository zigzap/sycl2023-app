export function loadUserTask(userid, taskid, callback) {
    const url = `/sycl-api/tasks/${taskid}?userid=${userid}`;
    fetch(url)
    .then(data=>{return data.json()})
    .then(res=>{callback(res);});
}
