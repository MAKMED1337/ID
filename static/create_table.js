function snakeToTitle(snakeStr) {
    return snakeStr
        .split('_')                 // Split the string into an array of words
        .map(word =>                // Map over each word
            word.charAt(0).toUpperCase() + word.slice(1)  // Capitalize the first letter and concatenate with the rest of the word
        )
        .join(' ');                 // Join the array back into a single string with spaces
}

function createTable(headers) {
    // Create table element
    const table = document.createElement('table');

    // Create the header row
    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');

    headers.forEach(headerText => {
        const th = document.createElement('th');
        th.textContent = headerText;
        headerRow.appendChild(th);
    });

    thead.appendChild(headerRow);
    table.appendChild(thead);

    // Create tbody element
    const tbody = document.createElement('tbody');
    table.appendChild(tbody);

    return table;
}

// TODO: check the order
async function fillTable(table, data) {
    const tableBody = table.getElementsByTagName('tbody')[0];
    tableBody.innerHTML = '';

    data.forEach(item => {
        const row = document.createElement('tr');

        for (let key in item)
            row.innerHTML += `<td>${item[key]}</td>`

        tableBody.appendChild(row);
    });
}

async function createTableFromFetch(path) {
    const token = localStorage.getItem('bearerToken');

    if (!token) {
        console.error('No bearer token found in localStorage');
        window.location.href = '/static/login.html';
        return;
    }

    try {
        const response = await fetch(path, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });

        if (response.status === 401) {
            window.location.href = '/static/login.html';
            return;
        }

        if (!response.ok) {
            throw Error('Network response was not ok ' + response.statusText);
        }

        const data = await response.json();
        if (data.length == 0)
            return null;

        const table = createTable(Object.keys(data[0]).map(snakeToTitle));
        fillTable(table, data);
        return table;
    } catch (error) {
        console.error('Error fetching passport data:', error);
    }
}
